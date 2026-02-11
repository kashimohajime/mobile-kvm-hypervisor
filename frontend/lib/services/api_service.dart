/// Service HTTP pour communiquer avec l'API backend Flask.
///
/// Gère les requêtes REST vers le backend KVM avec :
/// - Timeout configurable
/// - Retry automatique sur échec
/// - Gestion centralisée des erreurs
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/vm_model.dart';

/// Exception personnalisée pour les erreurs API.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  /// URL de base de l'API (ex: "http://192.168.1.100:5000")
  String baseUrl;

  /// Durée max d'attente pour une requête
  final Duration timeout;

  /// Nombre de tentatives en cas d'échec réseau
  final int maxRetries;

  /// Token d'authentification JWT
  String? _token;

  ApiService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 2,
  });

  /// Définit le token d'authentification.
  void setToken(String? token) {
    _token = token;
  }

  // ──────────────────────────────────────────────
  // Méthode HTTP générique avec retry
  // ──────────────────────────────────────────────

  /// Exécute une requête GET avec retry automatique.
  Future<dynamic> _get(String endpoint) async {
    return _requestWithRetry(() async {
      final headers = {
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
      final response = await http
          .get(Uri.parse('$baseUrl$endpoint'), headers: headers)
          .timeout(timeout);
      return _handleResponse(response);
    });
  }

  /// Exécute une requête POST avec retry automatique.
  Future<dynamic> _post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    return _requestWithRetry(() async {
      final headers = {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return _handleResponse(response);
    });
  }

  /// Exécute une requête DELETE avec retry automatique.
  Future<dynamic> _delete(String endpoint) async {
    return _requestWithRetry(() async {
      final headers = {
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
      final response = await http
          .delete(Uri.parse('$baseUrl$endpoint'), headers: headers)
          .timeout(timeout);
      return _handleResponse(response);
    });
  }

  /// Logique de retry : retente [maxRetries] fois en cas d'erreur réseau.
  Future<dynamic> _requestWithRetry(
    Future<dynamic> Function() request,
  ) async {
    int attempts = 0;
    while (true) {
      try {
        attempts++;
        return await request();
      } on SocketException catch (e) {
        if (attempts > maxRetries) {
          throw ApiException(
            'Impossible de se connecter au serveur. Vérifiez que le backend est démarré et l\'adresse IP est correcte.\n($e)',
          );
        }
        await Future.delayed(Duration(seconds: attempts));
      } on TimeoutException {
        if (attempts > maxRetries) {
          throw ApiException(
            'Le serveur ne répond pas (timeout). Vérifiez la connexion réseau.',
          );
        }
        await Future.delayed(Duration(seconds: attempts));
      } on ApiException {
        rethrow;
      } catch (e) {
        if (attempts > maxRetries) {
          throw ApiException('Erreur inattendue : $e');
        }
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  /// Traite la réponse HTTP et retourne le JSON (Map ou List).
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }

    // Tenter de parser le message d'erreur du backend
    String errorMessage;
    try {
      final body = jsonDecode(response.body);
      errorMessage = body['message'] ?? 'Erreur inconnue';
    } catch (_) {
      errorMessage = 'Erreur serveur (code ${response.statusCode})';
    }

    throw ApiException(errorMessage, statusCode: response.statusCode);
  }

  // ──────────────────────────────────────────────
  // Endpoints API
  // ──────────────────────────────────────────────

  /// POST /login — Authentification utilisateur.
  Future<String> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'];
        setToken(token);
        return token;
      } else {
        final body = jsonDecode(response.body);
        throw ApiException(body['msg'] ?? 'Identifiants incorrects',
            statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Erreur de connexion : $e');
    }
  }

  /// GET /health — Vérifie l'état de l'API.
  Future<Map<String, dynamic>> healthCheck() async {
    return await _get('/health') as Map<String, dynamic>;
  }

  /// GET /vms — Liste toutes les VMs.
  Future<List<VmModel>> listVms() async {
    final data = await _get('/vms') as Map<String, dynamic>;
    final vmsList = data['vms'] as List<dynamic>? ?? [];
    return vmsList.map((json) => VmModel.fromJson(json)).toList();
  }

  /// GET /vm/<name> — Détails d'une VM spécifique.
  Future<VmModel> getVmDetails(String name) async {
    final data = await _get('/vm/$name') as Map<String, dynamic>;
    return VmModel.fromJson(data);
  }

  /// GET /vm/<name>/metrics — Métriques temps réel d'une VM.
  Future<VmMetrics> getVmMetrics(String name) async {
    final data = await _get('/vm/$name/metrics') as Map<String, dynamic>;
    return VmMetrics.fromJson(data);
  }

  /// POST /vm/<name>/start — Démarrer une VM.
  Future<Map<String, dynamic>> startVm(String name) async {
    return await _post('/vm/$name/start') as Map<String, dynamic>;
  }

  /// POST /vm/<name>/stop — Arrêter une VM.
  Future<Map<String, dynamic>> stopVm(String name, {bool force = false}) async {
    return await _post('/vm/$name/stop', body: {'force': force})
        as Map<String, dynamic>;
  }

  /// POST /vm/<name>/restart — Redémarrer une VM.
  Future<Map<String, dynamic>> restartVm(String name) async {
    return await _post('/vm/$name/restart') as Map<String, dynamic>;
  }

  /// GET /stats/summary — Statistiques globales.
  Future<HostStats> getGlobalStats() async {
    final data = await _get('/stats/summary') as Map<String, dynamic>;
    return HostStats.fromJson(data);
  }

  // ──────────────────────────────────────────────
  // SNAPSHOTS
  // ──────────────────────────────────────────────

  /// GET /vm/<name>/snapshots
  Future<List<VmSnapshot>> getSnapshots(String name) async {
    final response = await _get('/vm/$name/snapshots');
    return (response as List).map((e) => VmSnapshot.fromJson(e)).toList();
  }

  /// POST /vm/<name>/snapshots
  Future<void> createSnapshot(
      String name, String snapshotName, String description) async {
    await _post('/vm/$name/snapshots', body: {
      'name': snapshotName,
      'description': description,
    });
  }

  /// POST /vm/<name>/snapshots/<snapshotName>/revert
  Future<void> revertSnapshot(String name, String snapshotName) async {
    await _post('/vm/$name/snapshots/$snapshotName/revert');
  }

  /// DELETE /vm/<name>/snapshots/<snapshotName>
  Future<void> deleteSnapshot(String name, String snapshotName) async {
    await _delete('/vm/$name/snapshots/$snapshotName');
  }

  // ──────────────────────────────────────────────
  // RESSOURCES
  // ──────────────────────────────────────────────

  /// POST /vm/<name>/resources
  Future<void> updateResources(String name, int vcpus, int memoryMb) async {
    await _post('/vm/$name/resources', body: {
      'vcpus': vcpus,
      'memory_mb': memoryMb,
    });
  }
}
