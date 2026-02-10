# 🖥️ KVM Supervisor — Backend API

API REST Flask pour la supervision et le contrôle de machines virtuelles KVM via **libvirt**.

---

## 📋 Prérequis

| Élément | Version minimale |
|---------|-----------------|
| Ubuntu (hôte KVM) | 20.04+ |
| Python | 3.10+ |
| KVM / QEMU | installé et fonctionnel |
| libvirt | installé (`libvirtd` actif) |

---

## 🚀 Installation

### 1. Installer les dépendances système

```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv \
                    libvirt-dev libvirt-daemon-system \
                    qemu-kvm virtinst bridge-utils
```

### 2. Vérifier que libvirt fonctionne

```bash
# Le service doit être actif
sudo systemctl status libvirtd

# Tester la connexion
virsh list --all
```

### 3. Ajouter votre utilisateur au groupe libvirt (évite d'avoir besoin de sudo)

```bash
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER
# Déconnectez-vous et reconnectez-vous pour appliquer
```

### 4. Créer l'environnement Python et installer les dépendances

```bash
cd backend/

# Créer un environnement virtuel
python3 -m venv venv
source venv/bin/activate

# Installer les dépendances
pip install -r requirements.txt
```

---

## ▶️ Lancement

### Mode développement

```bash
# Activer l'environnement virtuel (si pas déjà fait)
source venv/bin/activate

# Lancer le serveur
python app.py
```

Le serveur démarre sur **`http://0.0.0.0:5000`**.

### Variables d'environnement (optionnelles)

| Variable | Défaut | Description |
|----------|--------|-------------|
| `HOST` | `0.0.0.0` | Adresse d'écoute |
| `PORT` | `5000` | Port d'écoute |
| `FLASK_DEBUG` | `0` | Mode debug (`1` pour activer) |
| `LIBVIRT_URI` | `qemu:///system` | URI de connexion libvirt |

Exemple :
```bash
FLASK_DEBUG=1 PORT=8080 python app.py
```

### Mode production (avec Gunicorn)

```bash
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

---

## 📡 Endpoints de l'API

### Informations générales

| Méthode | Route | Description |
|---------|-------|-------------|
| `GET` | `/` | Informations sur l'API |
| `GET` | `/health` | État de santé de l'API et de libvirt |
| `GET` | `/stats/summary` | Statistiques globales (dashboard) |

### Gestion des VMs

| Méthode | Route | Description |
|---------|-------|-------------|
| `GET` | `/vms` | Lister toutes les VMs |
| `GET` | `/vm/<name>` | Détails d'une VM spécifique |
| `GET` | `/vm/<name>/metrics` | Métriques temps réel (CPU, RAM, disque, réseau) |
| `POST` | `/vm/<name>/start` | Démarrer une VM |
| `POST` | `/vm/<name>/stop` | Arrêter une VM (body optionnel : `{"force": true}`) |
| `POST` | `/vm/<name>/restart` | Redémarrer une VM |

---

## 📝 Exemples d'utilisation (curl)

### Lister les VMs

```bash
curl http://localhost:5000/vms
```

Réponse :
```json
{
  "count": 2,
  "vms": [
    {
      "name": "ubuntu-server",
      "state": "running",
      "vcpus": 2,
      "memory_mb": 2048,
      "is_active": true
    },
    {
      "name": "debian-test",
      "state": "stopped",
      "vcpus": 1,
      "memory_mb": 1024,
      "is_active": false
    }
  ]
}
```

### Démarrer une VM

```bash
curl -X POST http://localhost:5000/vm/ubuntu-server/start
```

### Arrêter une VM (arrêt gracieux)

```bash
curl -X POST http://localhost:5000/vm/ubuntu-server/stop
```

### Arrêter une VM (arrêt forcé)

```bash
curl -X POST http://localhost:5000/vm/ubuntu-server/stop \
  -H "Content-Type: application/json" \
  -d '{"force": true}'
```

### Métriques temps réel

```bash
curl http://localhost:5000/vm/ubuntu-server/metrics
```

Réponse :
```json
{
  "name": "ubuntu-server",
  "state": "running",
  "cpu_percent": 12.5,
  "vcpus": 2,
  "memory_percent": 45.2,
  "memory_used_mb": 925,
  "memory_total_mb": 2048,
  "disk_io": [
    {
      "device": "vda",
      "read_bytes": 1048576,
      "write_bytes": 524288
    }
  ],
  "network_io": [
    {
      "interface": "vnet0",
      "rx_bytes": 2097152,
      "tx_bytes": 1048576
    }
  ]
}
```

### Vérifier l'état de l'API

```bash
curl http://localhost:5000/health
```

---

## 🔌 WebSocket (temps réel)

Si `flask-socketio` est installé, le serveur accepte les connexions WebSocket.

### Événements disponibles

| Événement (client → serveur) | Payload | Réponse |
|------------------------------|---------|---------|
| `request_metrics` | `{"name": "vm-name"}` | `vm_metrics` |
| `request_all_metrics` | *(aucun)* | `all_metrics` |
| `request_vms_list` | *(aucun)* | `vms_list` |

### Exemple Flutter (socket_io_client)

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

final socket = IO.io('http://192.168.1.100:5000', <String, dynamic>{
  'transports': ['websocket'],
});

socket.on('connect', (_) => print('Connecté'));
socket.on('vm_metrics', (data) => print('Métriques: $data'));

// Demander les métriques d'une VM
socket.emit('request_metrics', {'name': 'ubuntu-server'});
```

---

## 🗂️ Structure du projet

```
backend/
├── app.py                 # Routes Flask + WebSocket
├── libvirt_manager.py     # Logique libvirt (isolée)
├── requirements.txt       # Dépendances Python
└── README.md              # Ce fichier
```

---

## 🔧 Dépannage

### `libvirt.open() failed`
→ Vérifiez que `libvirtd` tourne : `sudo systemctl start libvirtd`

### `Permission denied`
→ Ajoutez votre utilisateur au groupe `libvirt` : `sudo usermod -aG libvirt $USER`

### `libvirt-python` ne s'installe pas
→ Installez les headers : `sudo apt install libvirt-dev pkg-config`

### L'app mobile ne se connecte pas
→ Vérifiez que le firewall autorise le port 5000 :
```bash
sudo ufw allow 5000/tcp
```
→ Depuis l'émulateur Android, utilisez `10.0.2.2:5000` au lieu de `localhost`.

---

## 📄 Licence

Projet académique — Supervision d'hyperviseur KVM.
