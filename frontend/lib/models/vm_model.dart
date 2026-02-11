/// Modèle de données pour une machine virtuelle KVM.
///
/// Représente les informations de base, les détails complets
/// et les métriques temps réel d'une VM.
library;

class VmModel {
  final String name;
  final String uuid;
  final String state;
  final int vcpus;
  final int memoryMb;
  final int usedMemoryMb;
  final int? uptimeSeconds;
  final bool isActive;

  // Détails étendus (optionnels)
  final List<String> disks;
  final List<String> networkInterfaces;
  final String? osType;
  final bool? autostart;
  final bool? isPersistent;

  // Métriques temps réel (optionnelles)
  final double? cpuPercent;
  final double? memoryPercent;
  final int? memoryUsedMb;
  final int? memoryTotalMb;
  final List<DiskIo> diskIo;
  final List<NetworkIo> networkIo;

  VmModel({
    required this.name,
    this.uuid = '',
    required this.state,
    required this.vcpus,
    required this.memoryMb,
    this.usedMemoryMb = 0,
    this.uptimeSeconds,
    required this.isActive,
    this.disks = const [],
    this.networkInterfaces = const [],
    this.osType,
    this.autostart,
    this.isPersistent,
    this.cpuPercent,
    this.memoryPercent,
    this.memoryUsedMb,
    this.memoryTotalMb,
    this.diskIo = const [],
    this.networkIo = const [],
  });

  /// Parse depuis le JSON de l'API (liste / détails).
  factory VmModel.fromJson(Map<String, dynamic> json) {
    return VmModel(
      name: json['name'] ?? 'Inconnu',
      uuid: json['uuid'] ?? '',
      state: json['state'] ?? 'unknown',
      vcpus: json['vcpus'] ?? 0,
      memoryMb: json['memory_mb'] ?? 0,
      usedMemoryMb: json['used_memory_mb'] ?? 0,
      uptimeSeconds: json['uptime_seconds'],
      isActive: json['is_active'] ?? false,
      disks: List<String>.from(json['disks'] ?? []),
      networkInterfaces: List<String>.from(json['network_interfaces'] ?? []),
      osType: json['os_type'],
      autostart: json['autostart'],
      isPersistent: json['is_persistent'],
    );
  }

  /// Crée un VmModel enrichi avec les métriques temps réel.
  VmModel copyWithMetrics(VmMetrics metrics) {
    return VmModel(
      name: name,
      uuid: uuid,
      state: metrics.state ?? state,
      vcpus: metrics.vcpus ?? vcpus,
      memoryMb: memoryMb,
      usedMemoryMb: usedMemoryMb,
      uptimeSeconds: uptimeSeconds,
      isActive: isActive,
      disks: disks,
      networkInterfaces: networkInterfaces,
      osType: osType,
      autostart: autostart,
      isPersistent: isPersistent,
      cpuPercent: metrics.cpuPercent,
      memoryPercent: metrics.memoryPercent,
      memoryUsedMb: metrics.memoryUsedMb,
      memoryTotalMb: metrics.memoryTotalMb,
      diskIo: metrics.diskIo,
      networkIo: metrics.networkIo,
    );
  }

  /// Retourne true si la VM est en cours d'exécution.
  bool get isRunning => state == 'running';

  /// Retourne true si la VM est arrêtée.
  bool get isStopped => state == 'stopped' || state == 'shutoff';

  /// Retourne true si la VM est en pause.
  bool get isPaused => state == 'paused';

  /// Formatte l'uptime en chaîne lisible (ex: "2h 15m 30s").
  String get formattedUptime {
    if (uptimeSeconds == null || uptimeSeconds == 0) return '—';
    final h = uptimeSeconds! ~/ 3600;
    final m = (uptimeSeconds! % 3600) ~/ 60;
    final s = uptimeSeconds! % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Formatte la RAM en chaîne lisible.
  String get formattedMemory {
    if (memoryMb >= 1024) {
      return '${(memoryMb / 1024).toStringAsFixed(1)} Go';
    }
    return '$memoryMb Mo';
  }
}

/// Métriques temps réel d'une VM.
class VmMetrics {
  final String? state;
  final double cpuPercent;
  final int? vcpus;
  final double memoryPercent;
  final int memoryUsedMb;
  final int memoryTotalMb;
  final List<DiskIo> diskIo;
  final List<NetworkIo> networkIo;

  VmMetrics({
    this.state,
    required this.cpuPercent,
    this.vcpus,
    required this.memoryPercent,
    required this.memoryUsedMb,
    required this.memoryTotalMb,
    this.diskIo = const [],
    this.networkIo = const [],
  });

  factory VmMetrics.fromJson(Map<String, dynamic> json) {
    return VmMetrics(
      state: json['state'],
      cpuPercent: (json['cpu_percent'] ?? 0).toDouble(),
      vcpus: json['vcpus'],
      memoryPercent: (json['memory_percent'] ?? 0).toDouble(),
      memoryUsedMb: json['memory_used_mb'] ?? 0,
      memoryTotalMb: json['memory_total_mb'] ?? 0,
      diskIo: (json['disk_io'] as List<dynamic>?)
              ?.map((d) => DiskIo.fromJson(d))
              .toList() ??
          [],
      networkIo: (json['network_io'] as List<dynamic>?)
              ?.map((n) => NetworkIo.fromJson(n))
              .toList() ??
          [],
    );
  }
}

/// Statistiques I/O disque.
class DiskIo {
  final String device;
  final int readBytes;
  final int writeBytes;
  final int readRequests;
  final int writeRequests;
  final int errors;

  DiskIo({
    required this.device,
    required this.readBytes,
    required this.writeBytes,
    this.readRequests = 0,
    this.writeRequests = 0,
    this.errors = 0,
  });

  factory DiskIo.fromJson(Map<String, dynamic> json) {
    return DiskIo(
      device: json['device'] ?? '',
      readBytes: json['read_bytes'] ?? 0,
      writeBytes: json['write_bytes'] ?? 0,
      readRequests: json['read_requests'] ?? 0,
      writeRequests: json['write_requests'] ?? 0,
      errors: json['errors'] ?? 0,
    );
  }

  /// Formatte les octets en chaîne lisible (Ko, Mo, Go).
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
  }
}

/// Statistiques I/O réseau.
class NetworkIo {
  final String interface_;
  final int rxBytes;
  final int rxPackets;
  final int rxErrors;
  final int rxDrops;
  final int txBytes;
  final int txPackets;
  final int txErrors;
  final int txDrops;

  NetworkIo({
    required this.interface_,
    required this.rxBytes,
    this.rxPackets = 0,
    this.rxErrors = 0,
    this.rxDrops = 0,
    required this.txBytes,
    this.txPackets = 0,
    this.txErrors = 0,
    this.txDrops = 0,
  });

  factory NetworkIo.fromJson(Map<String, dynamic> json) {
    return NetworkIo(
      interface_: json['interface'] ?? '',
      rxBytes: json['rx_bytes'] ?? 0,
      rxPackets: json['rx_packets'] ?? 0,
      rxErrors: json['rx_errors'] ?? 0,
      rxDrops: json['rx_drops'] ?? 0,
      txBytes: json['tx_bytes'] ?? 0,
      txPackets: json['tx_packets'] ?? 0,
      txErrors: json['tx_errors'] ?? 0,
      txDrops: json['tx_drops'] ?? 0,
    );
  }
}

/// Statistiques globales de l'hyperviseur (pour /stats/summary).
class HostStats {
  final HostInfo host;
  final int vmsTotal;
  final int vmsActive;
  final int vmsInactive;
  final Map<String, int> stateDistribution;
  final List<VmModel> vms;

  HostStats({
    required this.host,
    required this.vmsTotal,
    required this.vmsActive,
    required this.vmsInactive,
    required this.stateDistribution,
    required this.vms,
  });

  factory HostStats.fromJson(Map<String, dynamic> json) {
    return HostStats(
      host: HostInfo.fromJson(json['host'] ?? {}),
      vmsTotal: json['vms_total'] ?? 0,
      vmsActive: json['vms_active'] ?? 0,
      vmsInactive: json['vms_inactive'] ?? 0,
      stateDistribution: Map<String, int>.from(json['state_distribution'] ?? {}),
      vms: (json['vms'] as List<dynamic>?)
              ?.map((v) => VmModel.fromJson(v))
              .toList() ??
          [],
    );
  }
}

/// Informations sur l'hôte hyperviseur.
class HostInfo {
  final String hostname;
  final String cpuModel;
  final int memoryTotalMb;
  final int cpus;
  final int cpuFrequencyMhz;
  final String libvirtVersion;
  final String hypervisorType;

  HostInfo({
    required this.hostname,
    required this.cpuModel,
    required this.memoryTotalMb,
    required this.cpus,
    required this.cpuFrequencyMhz,
    required this.libvirtVersion,
    required this.hypervisorType,
  });

  factory HostInfo.fromJson(Map<String, dynamic> json) {
    return HostInfo(
      hostname: json['hostname'] ?? '',
      cpuModel: json['cpu_model'] ?? '',
      memoryTotalMb: json['memory_total_mb'] ?? 0,
      cpus: json['cpus'] ?? 0,
      cpuFrequencyMhz: json['cpu_frequency_mhz'] ?? 0,
      libvirtVersion: json['libvirt_version'] ?? '',
      hypervisorType: json['hypervisor_type'] ?? '',
    );
  }

  /// Formatte la RAM hôte en chaîne lisible.
  String get formattedMemory {
    if (memoryTotalMb >= 1024) {
      return '${(memoryTotalMb / 1024).toStringAsFixed(1)} Go';
    }
    return '$memoryTotalMb Mo';
  }
}
