"""
app.py
======
Application Flask principale exposant une API RESTful pour la
supervision et le contrôle de machines virtuelles KVM via libvirt.

Points d'entrée :
    GET  /                      → Bienvenue / info API
    GET  /health                → Vérification état de l'API
    GET  /vms                   → Liste de toutes les VMs
    GET  /vm/<name>             → Détails d'une VM
    GET  /vm/<name>/metrics     → Métriques temps réel d'une VM
    POST /vm/<name>/start       → Démarrer une VM
    POST /vm/<name>/stop        → Arrêter une VM
    POST /vm/<name>/restart     → Redémarrer une VM
    GET  /stats/summary         → Stats globales de l'hyperviseur

WebSocket (via flask-socketio) :
    Event "request_metrics"     → Envoie les métriques d'une VM
    Event "request_all_metrics" → Envoie les métriques de toutes les VMs
"""

import logging
import os
import sys
from datetime import datetime, timezone

from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from werkzeug.security import generate_password_hash, check_password_hash
import sqlite3

# ──── Import optionnel de flask-socketio ──────
try:
    from flask_socketio import SocketIO, emit
    HAS_SOCKETIO = True
except ImportError:
    HAS_SOCKETIO = False

from libvirt_manager import (
    LibvirtManager,
    LibvirtConnectionError,
    LibvirtError,
    VMNotFoundError,
)

# ──────────────────────────────────────────────
# Configuration du logging
# ──────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  [%(levelname)s]  %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger("kvm-supervisor")

# ──────────────────────────────────────────────
# Initialisation Flask & JWT
# ──────────────────────────────────────────────
app = Flask(__name__)

# Configuration JWT
from datetime import timedelta
app.config["JWT_SECRET_KEY"] = os.environ.get("JWT_SECRET_KEY", "super-secret-key-change-me")
app.config["JWT_ACCESS_TOKEN_EXPIRES"] = timedelta(days=7)
jwt = JWTManager(app)

# ── Base de donnéesAuth (SQLite) ──────────────
DB_NAME = "kvm_auth.db"

def init_db():
    """Initialise la base de données utilisateurs."""
    try:
        conn = sqlite3.connect(DB_NAME)
        c = conn.cursor()
        c.execute('''CREATE TABLE IF NOT EXISTS users
                     (username TEXT PRIMARY KEY, password_hash TEXT)''')
        
        # Vérifier si admin existe
        c.execute("SELECT * FROM users WHERE username='admin'")
        if not c.fetchone():
            # Mot de passe par défaut : admin
            p_hash = generate_password_hash("admin")
            c.execute("INSERT INTO users VALUES ('admin', ?)", (p_hash,))
            logger.info("INIT: Utilisateur 'admin' créé (mdp: 'admin')")
        
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error("Erreur initialisation DB auth : %s", e)

try:
    init_db()
except Exception as e:
    logger.warning("Impossible d'initialiser la DB Auth : %s", e)

# CORS : autorise toutes les origines (nécessaire pour Flutter mobile)
CORS(app, resources={r"/*": {"origins": "*"}})

# URI libvirt configurable via variable d'environnement
LIBVIRT_URI = os.environ.get("LIBVIRT_URI", "qemu:///system")
manager = LibvirtManager(uri=LIBVIRT_URI)

# ──── WebSocket (optionnel) ───────────────────
if HAS_SOCKETIO:
    socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")
    logger.info("Flask-SocketIO activé — WebSocket disponible")
else:
    socketio = None
    logger.warning(
        "flask-socketio non installé — les WebSockets ne seront pas disponibles. "
        "Installez-le avec : pip install flask-socketio"
    )

# ──────────────────────────────────────────────
# Date de démarrage (pour /health)
# ──────────────────────────────────────────────
START_TIME = datetime.now(timezone.utc)


# ==============================================================
#  GESTIONNAIRES D'ERREURS
# ==============================================================

@app.errorhandler(VMNotFoundError)
def handle_vm_not_found(error):
    """Retourne 404 lorsque la VM demandée n'existe pas."""
    logger.warning("VM introuvable : %s", error)
    return jsonify({
        "error": "vm_not_found",
        "message": str(error),
    }), 404


@app.errorhandler(LibvirtConnectionError)
def handle_libvirt_connection(error):
    """Retourne 503 lorsque la connexion à libvirt échoue."""
    logger.error("Connexion libvirt échouée : %s", error)
    return jsonify({
        "error": "libvirt_unavailable",
        "message": str(error),
    }), 503


@app.errorhandler(LibvirtError)
def handle_libvirt_error(error):
    """Retourne 500 pour les erreurs libvirt génériques."""
    logger.error("Erreur libvirt : %s", error)
    return jsonify({
        "error": "libvirt_error",
        "message": str(error),
    }), 500


@app.errorhandler(404)
def handle_not_found(error):
    """Route inexistante."""
    return jsonify({
        "error": "not_found",
        "message": "La ressource demandée n'existe pas.",
    }), 404


@app.errorhandler(500)
def handle_internal(error):
    """Erreur serveur inattendue."""
    logger.exception("Erreur interne inattendue")
    return jsonify({
        "error": "internal_error",
        "message": "Une erreur interne est survenue.",
    }), 500


# ==============================================================
#  ROUTES AUTH
# ==============================================================

@app.route("/login", methods=["POST"])
def login():
    """Authentification utilisateur."""
    username = request.json.get("username", None)
    password = request.json.get("password", None)
    
    if not username or not password:
        return jsonify({"msg": "Missing username or password"}), 400
    
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("SELECT password_hash FROM users WHERE username=?", (username,))
    row = c.fetchone()
    conn.close()
    
    if row and check_password_hash(row[0], password):
        access_token = create_access_token(identity=username)
        return jsonify(access_token=access_token)
    
    return jsonify({"msg": "Identifiants invalides"}), 401


# ==============================================================
#  ROUTES API (Protégées)
# ==============================================================

# ── Racine ────────────────────────────────────
@app.route("/", methods=["GET"])
def index():
    """Point d'entrée : présentation de l'API."""
    return jsonify({
        "name": "KVM Supervisor API",
        "version": "1.0.0",
        "description": "API REST pour la supervision d'hyperviseur KVM via libvirt",
        "endpoints": {
            "GET /":                  "Bienvenue / info",
            "GET /health":            "État de l'API",
            "GET /vms":               "Liste des VMs",
            "GET /vm/<name>":         "Détails d'une VM",
            "GET /vm/<name>/metrics": "Métriques temps réel",
            "POST /vm/<name>/start":  "Démarrer une VM",
            "POST /vm/<name>/stop":   "Arrêter une VM",
            "POST /vm/<name>/restart":"Redémarrer une VM",
            "GET /stats/summary":     "Statistiques globales",
        },
    })


# ── Health check ──────────────────────────────
@app.route("/health", methods=["GET"])
def health():
    """
    Vérifie l'état de l'API et de la connexion libvirt.
    Retourne 200 si tout est OK, 503 si libvirt est inaccessible.
    """
    uptime = (datetime.now(timezone.utc) - START_TIME).total_seconds()

    # Test rapide de connexion libvirt
    libvirt_ok = True
    libvirt_message = "Connecté"
    try:
        conn = manager._connect()
        conn.close()
    except LibvirtConnectionError as e:
        libvirt_ok = False
        libvirt_message = str(e)

    status_code = 200 if libvirt_ok else 503

    return jsonify({
        "status": "healthy" if libvirt_ok else "degraded",
        "uptime_seconds": round(uptime, 2),
        "started_at": START_TIME.isoformat(),
        "libvirt": {
            "connected": libvirt_ok,
            "message": libvirt_message,
            "uri": LIBVIRT_URI,
        },
        "websocket_available": HAS_SOCKETIO,
    }), status_code


# ── Liste des VMs ─────────────────────────────
# ── Liste des VMs ─────────────────────────────
@app.route("/vms", methods=["GET"])
@jwt_required()
def list_vms():
    """Retourne la liste de toutes les VMs avec leurs infos de base."""
    vms = manager.list_vms()
    return jsonify({
        "count": len(vms),
        "vms": vms,
    })


# ── Détails d'une VM ──────────────────────────
# ── Détails d'une VM ──────────────────────────
@app.route("/vm/<name>", methods=["GET"])
@jwt_required()
def vm_details(name: str):
    """Retourne les détails complets d'une VM spécifique."""
    details = manager.vm_details(name)
    return jsonify(details)


# ── Métriques temps réel d'une VM ─────────────
# ── Métriques temps réel d'une VM ─────────────
@app.route("/vm/<name>/metrics", methods=["GET"])
@jwt_required()
def vm_metrics(name: str):
    """
    Retourne les métriques en temps réel d'une VM :
    CPU%, RAM%, I/O disque, I/O réseau.
    """
    metrics = manager.vm_metrics(name)
    return jsonify(metrics)


# ── Démarrer une VM ───────────────────────────
# ── Démarrer une VM ───────────────────────────
@app.route("/vm/<name>/start", methods=["POST"])
@jwt_required()
def start_vm(name: str):
    """Démarre la VM spécifiée."""
    result = manager.start_vm(name)
    return jsonify(result)


# ── Arrêter une VM ────────────────────────────
# ── Arrêter une VM ────────────────────────────
@app.route("/vm/<name>/stop", methods=["POST"])
@jwt_required()
def stop_vm(name: str):
    """
    Arrête la VM spécifiée.
    Paramètre optionnel (JSON body) :
        force (bool) : si true, arrêt brutal (destroy). Défaut : false.
    """
    body = request.get_json(silent=True) or {}
    force = body.get("force", False)
    result = manager.stop_vm(name, force=force)
    return jsonify(result)


# ── Redémarrer une VM ─────────────────────────
# ── Redémarrer une VM ─────────────────────────
@app.route("/vm/<name>/restart", methods=["POST"])
@jwt_required()
def restart_vm(name: str):
    """Redémarre (reboot) la VM spécifiée."""
    result = manager.restart_vm(name)
    return jsonify(result)


# ── Stats globales (dashboard) ────────────────
# ── Stats globales (dashboard) ────────────────
@app.route("/stats/summary", methods=["GET"])
@jwt_required()
def stats_summary():
    """
    Retourne un résumé global : infos hôte, nombre de VMs,
    répartition par état, etc. Idéal pour un dashboard.
    """
    stats = manager.global_stats()
    return jsonify(stats)


# ── SNAPSHOTS ─────────────────────────────────

@app.route("/vm/<name>/snapshots", methods=["GET"])
@jwt_required()
def list_snapshots(name):
    """Liste tous les snapshots d'une VM."""
    snapshots = manager.list_snapshots(name)
    return jsonify(snapshots)


@app.route("/vm/<name>/snapshots", methods=["POST"])
@jwt_required()
def create_snapshot(name):
    """Crée un nouveau snapshot."""
    body = request.get_json(silent=True) or {}
    snapshot_name = body.get("name")
    description = body.get("description", "")

    if not snapshot_name:
        return jsonify({"error": "missing_name", "message": "Le nom du snapshot est requis"}), 400

    result = manager.create_snapshot(name, snapshot_name, description)
    return jsonify(result), 201


@app.route("/vm/<name>/snapshots/<snapshot_name>/revert", methods=["POST"])
@jwt_required()
def revert_snapshot(name, snapshot_name):
    """Restaure la VM à l'état du snapshot."""
    result = manager.revert_snapshot(name, snapshot_name)
    return jsonify(result)


@app.route("/vm/<name>/snapshots/<snapshot_name>", methods=["DELETE"])
@jwt_required()
def delete_snapshot(name, snapshot_name):
    """Supprime un snapshot."""
    result = manager.delete_snapshot(name, snapshot_name)
    return jsonify(result)


# ── RESSOURCES ────────────────────────────────

@app.route("/vm/<name>/resources", methods=["POST"])
@jwt_required()
def update_resources(name):
    """Met à jour les ressources (vCPUs, RAM) de la VM."""
    body = request.get_json(silent=True) or {}
    vcpus = body.get("vcpus")
    memory_mb = body.get("memory_mb")

    if vcpus is None or memory_mb is None:
        return jsonify({"error": "missing_params", "message": "vcpus et memory_mb sont requis"}), 400

    try:
        result = manager.update_resources(name, int(vcpus), int(memory_mb))
        return jsonify(result)
    except ValueError:
        return jsonify({"error": "invalid_params", "message": "vcpus et memory_mb doivent être des entiers"}), 400


# ==============================================================
#  WEBSOCKET EVENTS (optionnel)
# ==============================================================

if HAS_SOCKETIO and socketio is not None:

    @socketio.on("connect")
    def ws_connect():
        """Client WebSocket connecté."""
        logger.info("Client WebSocket connecté")
        emit("connected", {"message": "Connexion WebSocket établie"})

    @socketio.on("disconnect")
    def ws_disconnect():
        """Client WebSocket déconnecté."""
        logger.info("Client WebSocket déconnecté")

    @socketio.on("request_metrics")
    def ws_request_metrics(data):
        """
        Le client envoie : {"name": "ma-vm"}
        Le serveur répond avec les métriques de cette VM.
        """
        name = data.get("name", "")
        if not name:
            emit("error", {"message": "Le champ 'name' est requis."})
            return

        try:
            metrics = manager.vm_metrics(name)
            emit("vm_metrics", metrics)
        except VMNotFoundError as e:
            emit("error", {"message": str(e)})
        except LibvirtError as e:
            emit("error", {"message": str(e)})

    @socketio.on("request_all_metrics")
    def ws_request_all_metrics(data=None):
        """
        Envoie les métriques de toutes les VMs actives.
        """
        try:
            vms = manager.list_vms()
            all_metrics = []
            for vm in vms:
                if vm["is_active"]:
                    try:
                        m = manager.vm_metrics(vm["name"])
                        all_metrics.append(m)
                    except LibvirtError:
                        pass
            emit("all_metrics", {"vms": all_metrics})
        except LibvirtError as e:
            emit("error", {"message": str(e)})

    @socketio.on("request_vms_list")
    def ws_request_vms_list(data=None):
        """Envoie la liste des VMs via WebSocket."""
        try:
            vms = manager.list_vms()
            emit("vms_list", {"count": len(vms), "vms": vms})
        except LibvirtError as e:
            emit("error", {"message": str(e)})


# ==============================================================
#  POINT D'ENTRÉE
# ==============================================================

if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", 5000))
    debug = os.environ.get("FLASK_DEBUG", "0") == "1"

    logger.info("=" * 60)
    logger.info("  KVM Supervisor API")
    logger.info("  Écoute sur %s:%d", host, port)
    logger.info("  URI libvirt : %s", LIBVIRT_URI)
    logger.info("  Debug : %s", debug)
    logger.info("  WebSocket : %s", "activé" if HAS_SOCKETIO else "désactivé")
    logger.info("=" * 60)

    if HAS_SOCKETIO and socketio is not None:
        socketio.run(app, host=host, port=port, debug=debug, allow_unsafe_werkzeug=True)
    else:
        app.run(host=host, port=port, debug=debug)
