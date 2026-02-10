"""
libvirt_manager.py
==================
Module isolé pour la gestion des interactions avec libvirt / KVM.
Toutes les opérations sur les machines virtuelles passent par la classe
LibvirtManager afin de garder le code Flask (app.py) propre et découplé.
"""

import logging
import time
import xml.etree.ElementTree as ET

import libvirt

# ──────────────────────────────────────────────
# Configuration du logger
# ──────────────────────────────────────────────
logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────
# Constantes : mapping des états libvirt
# ──────────────────────────────────────────────
VM_STATE_MAP = {
    libvirt.VIR_DOMAIN_NOSTATE:     "no_state",
    libvirt.VIR_DOMAIN_RUNNING:     "running",
    libvirt.VIR_DOMAIN_BLOCKED:     "blocked",
    libvirt.VIR_DOMAIN_PAUSED:      "paused",
    libvirt.VIR_DOMAIN_SHUTDOWN:    "shutdown",
    libvirt.VIR_DOMAIN_SHUTOFF:     "stopped",
    libvirt.VIR_DOMAIN_CRASHED:     "crashed",
    libvirt.VIR_DOMAIN_PMSUSPENDED: "suspended",
}


class LibvirtError(Exception):
    """Exception personnalisée pour les erreurs libvirt."""
    pass


class VMNotFoundError(LibvirtError):
    """Levée lorsque la VM demandée n'existe pas."""
    pass


class LibvirtConnectionError(LibvirtError):
    """Levée lorsque la connexion à libvirt échoue."""
    pass


class LibvirtManager:
    """
    Gestionnaire libvirt — fournit une interface haut niveau pour
    lister, contrôler et superviser les VMs KVM.
    """

    def __init__(self, uri: str = "qemu:///system"):
        """
        Paramètres
        ----------
        uri : str
            URI de connexion libvirt (par défaut : qemu:///system pour
            une installation KVM locale).
        """
        self.uri = uri
        # Cache léger pour le calcul du CPU%
        self._cpu_cache: dict[str, dict] = {}

    # ──────────────────────────────────────────
    # Connexion
    # ──────────────────────────────────────────
    def _connect(self) -> libvirt.virConnect:
        """Ouvre une connexion à l'hyperviseur. Lève LibvirtConnectionError en cas d'échec."""
        try:
            conn = libvirt.open(self.uri)
            if conn is None:
                raise LibvirtConnectionError("libvirt.open() a retourné None")
            return conn
        except libvirt.libvirtError as e:
            logger.error("Connexion libvirt impossible : %s", e)
            raise LibvirtConnectionError(f"Impossible de se connecter à libvirt : {e}")

    # ──────────────────────────────────────────
    # Recherche d'une VM par nom
    # ──────────────────────────────────────────
    def _get_domain(self, conn: libvirt.virConnect, name: str) -> libvirt.virDomain:
        """Récupère un domaine par nom. Lève VMNotFoundError si introuvable."""
        try:
            dom = conn.lookupByName(name)
            return dom
        except libvirt.libvirtError:
            raise VMNotFoundError(f"VM '{name}' introuvable")

    # ──────────────────────────────────────────
    # Helpers XML
    # ──────────────────────────────────────────
    @staticmethod
    def _parse_xml(dom: libvirt.virDomain) -> ET.Element:
        """Parse le XML de description d'un domaine."""
        xml_str = dom.XMLDesc(0)
        return ET.fromstring(xml_str)

    @staticmethod
    def _get_max_memory_from_xml(root: ET.Element) -> int:
        """Retourne la RAM max configurée (en KiB) depuis le XML."""
        mem_elem = root.find("memory")
        if mem_elem is not None and mem_elem.text:
            return int(mem_elem.text)
        return 0

    @staticmethod
    def _get_vcpus_from_xml(root: ET.Element) -> int:
        """Retourne le nombre de vCPUs configurés depuis le XML."""
        vcpu_elem = root.find("vcpu")
        if vcpu_elem is not None and vcpu_elem.text:
            return int(vcpu_elem.text)
        return 0

    @staticmethod
    def _get_disk_targets(root: ET.Element) -> list[str]:
        """Retourne la liste des périphériques disque (ex: vda, sda)."""
        targets = []
        for disk in root.findall(".//disk[@device='disk']/target"):
            dev = disk.get("dev")
            if dev:
                targets.append(dev)
        return targets

    @staticmethod
    def _get_network_interfaces(root: ET.Element) -> list[str]:
        """Retourne la liste des interfaces réseau (ex: vnet0)."""
        ifaces = []
        for iface in root.findall(".//interface/target"):
            dev = iface.get("dev")
            if dev:
                ifaces.append(dev)
        return ifaces

    # ──────────────────────────────────────────
    # Informations basiques d'une VM
    # ──────────────────────────────────────────
    def _vm_basic_info(self, dom: libvirt.virDomain) -> dict:
        """
        Retourne les informations de base d'une VM :
        nom, état, vCPUs, RAM (MiB), UUID, uptime estimé.
        """
        state_id, max_mem_kib, mem_kib, vcpus, cpu_time_ns = dom.info()
        state_str = VM_STATE_MAP.get(state_id, "unknown")

        root = self._parse_xml(dom)
        max_mem_xml = self._get_max_memory_from_xml(root)
        vcpus_xml = self._get_vcpus_from_xml(root)

        # Calcul de l'uptime approximatif (si la VM tourne)
        uptime_seconds = None
        if state_id == libvirt.VIR_DOMAIN_RUNNING and cpu_time_ns > 0:
            # cpu_time est le temps CPU cumulé — pas exactement un uptime
            # On tente de récupérer une valeur plus fiable si disponible
            try:
                # Certaines versions de libvirt exposent un vrai uptime
                uptime_seconds = int(cpu_time_ns / 1_000_000_000)
            except Exception:
                uptime_seconds = None

        return {
            "name":       dom.name(),
            "uuid":       dom.UUIDString(),
            "state":      state_str,
            "vcpus":      vcpus_xml or vcpus,
            "memory_mb":  round((max_mem_xml or max_mem_kib) / 1024),
            "used_memory_mb": round(mem_kib / 1024),
            "uptime_seconds": uptime_seconds,
            "is_active":  dom.isActive() == 1,
        }

    # ──────────────────────────────────────────
    # LISTE DES VMs
    # ──────────────────────────────────────────
    def list_vms(self) -> list[dict]:
        """Liste toutes les VMs (actives et inactives) avec leurs infos de base."""
        conn = self._connect()
        try:
            vms = []
            # VMs actives (en cours d'exécution)
            for dom_id in conn.listDomainsID():
                try:
                    dom = conn.lookupByID(dom_id)
                    vms.append(self._vm_basic_info(dom))
                except libvirt.libvirtError as e:
                    logger.warning("Erreur lecture VM id=%s : %s", dom_id, e)

            # VMs définies mais arrêtées
            for name in conn.listDefinedDomains():
                try:
                    dom = conn.lookupByName(name)
                    vms.append(self._vm_basic_info(dom))
                except libvirt.libvirtError as e:
                    logger.warning("Erreur lecture VM '%s' : %s", name, e)

            logger.info("Liste des VMs récupérée : %d VM(s)", len(vms))
            return vms
        finally:
            conn.close()

    # ──────────────────────────────────────────
    # DÉTAILS D'UNE VM
    # ──────────────────────────────────────────
    def vm_details(self, name: str) -> dict:
        """Retourne les détails complets d'une VM spécifique."""
        conn = self._connect()
        try:
            dom = self._get_domain(conn, name)
            info = self._vm_basic_info(dom)
            root = self._parse_xml(dom)

            # Ajout d'infos supplémentaires
            info["disks"] = self._get_disk_targets(root)
            info["network_interfaces"] = self._get_network_interfaces(root)

            # OS info
            os_type_elem = root.find(".//os/type")
            info["os_type"] = os_type_elem.text if os_type_elem is not None else "unknown"

            # Autostart
            try:
                info["autostart"] = dom.autostart() == 1
            except libvirt.libvirtError:
                info["autostart"] = None

            # Persistent ?
            info["is_persistent"] = dom.isPersistent() == 1

            logger.info("Détails récupérés pour la VM '%s'", name)
            return info
        finally:
            conn.close()

    # ──────────────────────────────────────────
    # ACTIONS : start / stop / restart
    # ──────────────────────────────────────────
    def start_vm(self, name: str) -> dict:
        """Démarre une VM. Retourne un dict de statut."""
        conn = self._connect()
        try:
            dom = self._get_domain(conn, name)
            if dom.isActive():
                return {"status": "already_running", "name": name,
                        "message": f"La VM '{name}' est déjà en cours d'exécution."}
            dom.create()
            logger.info("VM '%s' démarrée avec succès", name)
            return {"status": "started", "name": name,
                    "message": f"La VM '{name}' a été démarrée."}
        except libvirt.libvirtError as e:
            logger.error("Échec démarrage VM '%s' : %s", name, e)
            raise LibvirtError(f"Impossible de démarrer la VM '{name}' : {e}")
        finally:
            conn.close()

    def stop_vm(self, name: str, force: bool = False) -> dict:
        """
        Arrête une VM.
        - force=False : arrêt gracieux (ACPI shutdown)
        - force=True  : arrêt brutal (destroy)
        """
        conn = self._connect()
        try:
            dom = self._get_domain(conn, name)
            if not dom.isActive():
                return {"status": "already_stopped", "name": name,
                        "message": f"La VM '{name}' est déjà arrêtée."}

            if force:
                dom.destroy()
                logger.info("VM '%s' arrêtée de force (destroy)", name)
            else:
                dom.shutdown()
                logger.info("VM '%s' arrêt gracieux demandé", name)

            return {"status": "stopped", "name": name,
                    "message": f"La VM '{name}' a été arrêtée{' (force)' if force else ''}."}
        except libvirt.libvirtError as e:
            logger.error("Échec arrêt VM '%s' : %s", name, e)
            raise LibvirtError(f"Impossible d'arrêter la VM '{name}' : {e}")
        finally:
            conn.close()

    def restart_vm(self, name: str) -> dict:
        """Redémarre une VM (reboot gracieux si active, sinon start)."""
        conn = self._connect()
        try:
            dom = self._get_domain(conn, name)
            if dom.isActive():
                dom.reboot(0)
                logger.info("VM '%s' redémarrée (reboot)", name)
                return {"status": "restarted", "name": name,
                        "message": f"La VM '{name}' a été redémarrée."}
            else:
                dom.create()
                logger.info("VM '%s' était arrêtée — démarrage", name)
                return {"status": "started", "name": name,
                        "message": f"La VM '{name}' était arrêtée, elle a été démarrée."}
        except libvirt.libvirtError as e:
            logger.error("Échec redémarrage VM '%s' : %s", name, e)
            raise LibvirtError(f"Impossible de redémarrer la VM '{name}' : {e}")
        finally:
            conn.close()

    # ──────────────────────────────────────────
    # MÉTRIQUES EN TEMPS RÉEL
    # ──────────────────────────────────────────
    def vm_metrics(self, name: str) -> dict:
        """
        Récupère les métriques en temps réel d'une VM :
        - CPU %  (calculé sur deux échantillons)
        - RAM %
        - I/O disque (lecture / écriture en octets)
        - Réseau   (rx / tx en octets)
        """
        conn = self._connect()
        try:
            dom = self._get_domain(conn, name)

            if not dom.isActive():
                return {
                    "name": name,
                    "state": "stopped",
                    "message": "Les métriques ne sont disponibles que pour les VMs en cours d'exécution.",
                    "cpu_percent": 0,
                    "memory_percent": 0,
                    "memory_used_mb": 0,
                    "memory_total_mb": 0,
                    "disk_io": [],
                    "network_io": [],
                }

            # ── CPU % ─────────────────────────────
            cpu_percent = self._compute_cpu_percent(dom, conn)

            # ── RAM ───────────────────────────────
            state_id, max_mem_kib, mem_kib, vcpus, cpu_time = dom.info()

            # Tenter d'obtenir les stats mémoire plus précises
            try:
                mem_stats = dom.memoryStats()
                actual_used = mem_stats.get("rss", mem_kib)  # Resident Set Size
                available = mem_stats.get("available", max_mem_kib)
                used_for_percent = mem_stats.get("actual", mem_kib)
            except libvirt.libvirtError:
                actual_used = mem_kib
                available = max_mem_kib
                used_for_percent = mem_kib

            memory_percent = round((actual_used / max_mem_kib) * 100, 2) if max_mem_kib > 0 else 0

            # ── Disque ────────────────────────────
            root = self._parse_xml(dom)
            disk_io = []
            for dev in self._get_disk_targets(root):
                try:
                    rd_req, rd_bytes, wr_req, wr_bytes, errs = dom.blockStats(dev)
                    disk_io.append({
                        "device": dev,
                        "read_bytes": rd_bytes,
                        "write_bytes": wr_bytes,
                        "read_requests": rd_req,
                        "write_requests": wr_req,
                        "errors": errs,
                    })
                except libvirt.libvirtError as e:
                    logger.warning("blockStats(%s) échoué : %s", dev, e)

            # ── Réseau ────────────────────────────
            network_io = []
            for iface in self._get_network_interfaces(root):
                try:
                    stats = dom.interfaceStats(iface)
                    # stats: (rx_bytes, rx_packets, rx_errs, rx_drop,
                    #         tx_bytes, tx_packets, tx_errs, tx_drop)
                    network_io.append({
                        "interface": iface,
                        "rx_bytes": stats[0],
                        "rx_packets": stats[1],
                        "rx_errors": stats[2],
                        "rx_drops": stats[3],
                        "tx_bytes": stats[4],
                        "tx_packets": stats[5],
                        "tx_errors": stats[6],
                        "tx_drops": stats[7],
                    })
                except libvirt.libvirtError as e:
                    logger.warning("interfaceStats(%s) échoué : %s", iface, e)

            metrics = {
                "name": name,
                "state": VM_STATE_MAP.get(state_id, "unknown"),
                "cpu_percent": cpu_percent,
                "vcpus": vcpus,
                "memory_percent": memory_percent,
                "memory_used_mb": round(actual_used / 1024),
                "memory_total_mb": round(max_mem_kib / 1024),
                "disk_io": disk_io,
                "network_io": network_io,
            }

            logger.debug("Métriques VM '%s' : %s", name, metrics)
            return metrics
        finally:
            conn.close()

    def _compute_cpu_percent(self, dom: libvirt.virDomain, conn: libvirt.virConnect) -> float:
        """
        Calcule le % CPU en prenant deux mesures espacées de ~1 seconde.
        Utilise un cache pour éviter de bloquer trop longtemps.
        """
        name = dom.name()

        # Première mesure (ou réutilisation du cache)
        now = time.time()
        prev = self._cpu_cache.get(name)

        info1 = dom.info()
        cpu_time_1 = info1[4]
        timestamp_1 = now

        if prev and (now - prev["timestamp"]) < 5:
            # Utiliser les données en cache comme « point de départ »
            cpu_time_0 = prev["cpu_time"]
            timestamp_0 = prev["timestamp"]
        else:
            # Pas de cache récent → on prend deux mesures
            cpu_time_0 = cpu_time_1
            timestamp_0 = timestamp_1
            time.sleep(1)
            info2 = dom.info()
            cpu_time_1 = info2[4]
            timestamp_1 = time.time()

        # Mettre à jour le cache
        self._cpu_cache[name] = {"cpu_time": cpu_time_1, "timestamp": timestamp_1}

        # Calcul du pourcentage
        dt = timestamp_1 - timestamp_0
        if dt <= 0:
            return 0.0

        num_cpus = dom.info()[3] or 1
        # cpu_time est en nanosecondes
        cpu_percent = ((cpu_time_1 - cpu_time_0) / (dt * num_cpus * 1e9)) * 100
        return round(max(0.0, min(cpu_percent, 100.0)), 2)

    # ──────────────────────────────────────────
    # STATS GLOBALES (dashboard)
    # ──────────────────────────────────────────
    def global_stats(self) -> dict:
        """
        Retourne un résumé global de l'hyperviseur :
        - Nombre de VMs (actives / total)
        - Info hôte (hostname, RAM totale, CPUs)
        - Répartition des états
        """
        conn = self._connect()
        try:
            # Infos hyperviseur
            hostname = conn.getHostname()
            node_info = conn.getInfo()
            # node_info: [model, mem_mb, cpus, mhz, nodes, sockets, cores, threads]
            host_info = {
                "hostname": hostname,
                "cpu_model": node_info[0],
                "memory_total_mb": node_info[1],
                "cpus": node_info[2],
                "cpu_frequency_mhz": node_info[3],
                "libvirt_version": self._format_version(conn.getLibVersion()),
                "hypervisor_type": conn.getType(),
            }

            # Comptage des VMs
            all_vms = self.list_vms()
            total = len(all_vms)
            active = sum(1 for vm in all_vms if vm["is_active"])

            # Répartition par état
            state_counts: dict[str, int] = {}
            for vm in all_vms:
                s = vm["state"]
                state_counts[s] = state_counts.get(s, 0) + 1

            return {
                "host": host_info,
                "vms_total": total,
                "vms_active": active,
                "vms_inactive": total - active,
                "state_distribution": state_counts,
                "vms": all_vms,
            }
        finally:
            conn.close()

    @staticmethod
    def _format_version(version_int: int) -> str:
        """Convertit un entier de version libvirt (ex: 9003000) en chaîne (ex: 9.3.0)."""
        major = version_int // 1_000_000
        minor = (version_int % 1_000_000) // 1_000
        patch = version_int % 1_000
        return f"{major}.{minor}.{patch}"
