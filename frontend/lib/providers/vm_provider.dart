/// Provider principal pour la gestion des VMs.
///
/// Gère :
/// - Le chargement et le cache de la liste des VMs
/// - Les métriques temps réel par VM
/// - Les actions (start, stop, restart)
/// - L'auto-refresh périodique
/// - La recherche / filtrage
/// - Les statistiques globales
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/vm_model.dart';
import '../services/api_service.dart';

/// États de chargement possibles.
enum LoadingState { idle, loading, loaded, error }

class VmProvider extends ChangeNotifier {
  // ── Service API ────────────────────────────
  final ApiService _apiService;

  VmProvider(this._apiService);

  // ── État : Liste des VMs ──────────────────
  List<VmModel> _vms = [];
  LoadingState _vmsState = LoadingState.idle;
  String? _vmsError;

  List<VmModel> get vms => _filteredVms;
  LoadingState get vmsState => _vmsState;
  String? get vmsError => _vmsError;

  // ── État : Détails VM ─────────────────────
  VmModel? _selectedVm;
  VmMetrics? _selectedVmMetrics;
  LoadingState _detailState = LoadingState.idle;
  String? _detailError;

  VmModel? get selectedVm => _selectedVm;
  VmMetrics? get selectedVmMetrics => _selectedVmMetrics;
  LoadingState get detailState => _detailState;
  String? get detailError => _detailError;

  // ── État : Stats globales ─────────────────
  HostStats? _hostStats;
  LoadingState _statsState = LoadingState.idle;
  String? _statsError;

  HostStats? get hostStats => _hostStats;
  LoadingState get statsState => _statsState;
  String? get statsError => _statsError;

  // ── Recherche / Filtre ────────────────────
  String _searchQuery = '';
  String? _stateFilter; // null = tous, 'running', 'stopped', etc.

  String get searchQuery => _searchQuery;
  String? get stateFilter => _stateFilter;

  /// VMs filtrées par recherche et état.
  List<VmModel> get _filteredVms {
    var result = _vms;

    // Filtre par nom
    if (_searchQuery.isNotEmpty) {
      result = result
          .where(
            (vm) => vm.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    // Filtre par état
    if (_stateFilter != null) {
      result = result.where((vm) => vm.state == _stateFilter).toList();
    }

    return result;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStateFilter(String? filter) {
    _stateFilter = filter;
    notifyListeners();
  }

  // ── Auto-refresh ──────────────────────────
  Timer? _autoRefreshTimer;
  bool _autoRefreshActive = false;

  bool get autoRefreshActive => _autoRefreshActive;

  /// Démarre l'auto-refresh toutes les [intervalSeconds] secondes.
  void startAutoRefresh({int intervalSeconds = 5}) {
    stopAutoRefresh();
    _autoRefreshActive = true;
    _autoRefreshTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => fetchVms(silent: true),
    );
    notifyListeners();
  }

  /// Arrête l'auto-refresh.
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _autoRefreshActive = false;
    notifyListeners();
  }

  /// Bascule l'auto-refresh.
  void toggleAutoRefresh({int intervalSeconds = 5}) {
    if (_autoRefreshActive) {
      stopAutoRefresh();
    } else {
      startAutoRefresh(intervalSeconds: intervalSeconds);
    }
  }

  // ──────────────────────────────────────────────
  // Actions : Chargement des données
  // ──────────────────────────────────────────────

  /// Charge la liste des VMs depuis l'API.
  ///
  /// [silent] = true pour ne pas afficher le loader (rafraîchissement en fond).
  Future<void> fetchVms({bool silent = false}) async {
    if (!silent) {
      _vmsState = LoadingState.loading;
      _vmsError = null;
      notifyListeners();
    }

    try {
      _vms = await _apiService.listVms();
      _vmsState = LoadingState.loaded;
      _vmsError = null;
    } on ApiException catch (e) {
      _vmsError = e.message;
      _vmsState = LoadingState.error;
    } catch (e) {
      _vmsError = 'Erreur inattendue : $e';
      _vmsState = LoadingState.error;
    }

    notifyListeners();
  }

  /// Charge les détails et métriques d'une VM spécifique.
  Future<void> fetchVmDetails(String name) async {
    _detailState = LoadingState.loading;
    _detailError = null;
    notifyListeners();

    try {
      // Charger détails et métriques en parallèle
      final results = await Future.wait([
        _apiService.getVmDetails(name),
        _apiService.getVmMetrics(name).catchError((_) => VmMetrics(
              cpuPercent: 0,
              memoryPercent: 0,
              memoryUsedMb: 0,
              memoryTotalMb: 0,
            )),
      ]);

      _selectedVm = results[0] as VmModel;
      _selectedVmMetrics = results[1] as VmMetrics;
      _detailState = LoadingState.loaded;
      _detailError = null;
    } on ApiException catch (e) {
      _detailError = e.message;
      _detailState = LoadingState.error;
    } catch (e) {
      _detailError = 'Erreur inattendue : $e';
      _detailState = LoadingState.error;
    }

    notifyListeners();
  }

  /// Rafraîchit les métriques d'une VM (sans recharger les détails).
  Future<void> refreshVmMetrics(String name) async {
    try {
      _selectedVmMetrics = await _apiService.getVmMetrics(name);
      notifyListeners();
    } catch (_) {
      // Silencieux — les métriques vont se rafraîchir au prochain cycle
    }
  }

  /// Charge les statistiques globales.
  Future<void> fetchGlobalStats() async {
    _statsState = LoadingState.loading;
    _statsError = null;
    notifyListeners();

    try {
      _hostStats = await _apiService.getGlobalStats();
      _statsState = LoadingState.loaded;
      _statsError = null;
    } on ApiException catch (e) {
      _statsError = e.message;
      _statsState = LoadingState.error;
    } catch (e) {
      _statsError = 'Erreur inattendue : $e';
      _statsState = LoadingState.error;
    }

    notifyListeners();
  }

  // ──────────────────────────────────────────────
  // Actions : Contrôle des VMs
  // ──────────────────────────────────────────────

  /// Démarre une VM. Retourne le message du serveur.
  Future<String> startVm(String name) async {
    try {
      final result = await _apiService.startVm(name);
      // Rafraîchir la liste et les détails
      await Future.wait([
        fetchVms(silent: true),
        if (_selectedVm?.name == name) fetchVmDetails(name),
      ]);
      return result['message'] ?? 'VM démarrée';
    } on ApiException catch (e) {
      throw e.message;
    }
  }

  /// Arrête une VM. Retourne le message du serveur.
  Future<String> stopVm(String name, {bool force = false}) async {
    try {
      final result = await _apiService.stopVm(name, force: force);
      await Future.wait([
        fetchVms(silent: true),
        if (_selectedVm?.name == name) fetchVmDetails(name),
      ]);
      return result['message'] ?? 'VM arrêtée';
    } on ApiException catch (e) {
      throw e.message;
    }
  }

  /// Redémarre une VM. Retourne le message du serveur.
  Future<String> restartVm(String name, {bool force = false}) async {
    try {
      final result = await _apiService.restartVm(name, force: force);
      await Future.wait([
        fetchVms(silent: true),
        if (_selectedVm?.name == name) fetchVmDetails(name),
      ]);
      return result['message'] ?? 'VM redémarrée';
    } on ApiException catch (e) {
      throw e.message;
    }
  }

  // ──────────────────────────────────────────────
  // SNAPSHOTS
  // ──────────────────────────────────────────────

  List<VmSnapshot> _snapshots = [];
  LoadingState _snapshotsState = LoadingState.idle;
  String? _snapshotsError;

  List<VmSnapshot> get snapshots => _snapshots;
  LoadingState get snapshotsState => _snapshotsState;
  String? get snapshotsError => _snapshotsError;

  /// Charge la liste des snapshots d'une VM.
  Future<void> fetchSnapshots(String vmName) async {
    _snapshotsState = LoadingState.loading;
    _snapshotsError = null;
    notifyListeners();

    try {
      _snapshots = await _apiService.getSnapshots(vmName);
      _snapshotsState = LoadingState.loaded;
    } on ApiException catch (e) {
      _snapshotsError = e.message;
      _snapshotsState = LoadingState.error;
    } catch (e) {
      _snapshotsError = 'Erreur inattendue : $e';
      _snapshotsState = LoadingState.error;
    }
    notifyListeners();
  }

  /// Crée un nouveau snapshot.
  Future<void> createSnapshot(
      String vmName, String snapshotName, String description) async {
    try {
      await _apiService.createSnapshot(vmName, snapshotName, description);
      await fetchSnapshots(vmName); // Rafraîchir la liste
    } on ApiException catch (e) {
      throw e.message;
    }
  }

  /// Restaure un snapshot.
  Future<void> revertSnapshot(String vmName, String snapshotName) async {
    try {
      await _apiService.revertSnapshot(vmName, snapshotName);
      await fetchVmDetails(vmName); // L'état de la VM a pu changer
    } on ApiException catch (e) {
      throw e.message;
    }
  }

  /// Supprime un snapshot.
  Future<void> deleteSnapshot(String vmName, String snapshotName) async {
    try {
      await _apiService.deleteSnapshot(vmName, snapshotName);
      await fetchSnapshots(vmName); // Rafraîchir la liste
    } on ApiException catch (e) {
      throw e.message;
    }
  }

  // ──────────────────────────────────────────────
  // RESSOURCES
  // ──────────────────────────────────────────────

  /// Met à jour les ressources CPU/RAM.
  Future<void> updateResources(String vmName, int vcpus, int memoryMb) async {
    try {
      await _apiService.updateResources(vmName, vcpus, memoryMb);
      await fetchVmDetails(vmName); // Mettre à jour les infos affichées
    } on ApiException catch (e) {
      throw e.message;
    }
  }

  // ──────────────────────────────────────────────
  // Compteurs rapides
  // ──────────────────────────────────────────────

  int get totalVms => _vms.length;
  int get runningVms => _vms.where((vm) => vm.isRunning).length;
  int get stoppedVms => _vms.where((vm) => vm.isStopped).length;

  // ──────────────────────────────────────────────
  // Nettoyage
  // ──────────────────────────────────────────────

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}
