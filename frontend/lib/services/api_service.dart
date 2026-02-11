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

  ApiService({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 2,
  });

  // ──────────────────────────────────────────────
  // Méthode HTTP générique avec retry
  // ──────────────────────────────────────────────

  /// Exécute une requête GET avec retry automatique.
  Future<Map<String, dynamic>> _get(String endpoint) async {
    return _requestWithRetry(() async {
      final response = await http
          .get(Uri.parse('$baseUrl$endpoint'))
          .timeout(timeout);
      return _handleResponse(response);
    });
  }

  /// Exécute une requête POST avec retry automatique.
  Future<Map<String, dynamic>> _post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    return _requestWithRetry(() async {
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);
      return _handleResponse(response);
    });
  }

  /// Logique de retry : retente [maxRetries] fois en cas d'erreur réseau.
  Future<Map<String, dynamic>> _requestWithRetry(
    Future<Map<String, dynamic>> Function() request,
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

  /// Traite la réponse HTTP et retourne le JSON.
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
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

  /// GET /health — Vérifie l'état de l'API.
  Future<Map<String, dynamic>> healthCheck() async {
    return _get('/health');
  }

  /// GET /vms — Liste toutes les VMs.
  Future<List<VmModel>> listVms() async {
    final data = await _get('/vms');
    final vmsList = data['vms'] as List<dynamic>? ?? [];
    return vmsList.map((json) => VmModel.fromJson(json)).toList();
  }

  /// GET /vm/<name> — Détails d'une VM spécifique.
  Future<VmModel> getVmDetails(String name) async {
    final data = await _get('/vm/$name');
    return VmModel.fromJson(data);
  }

  /// GET /vm/<name>/metrics — Métriques temps réel d'une VM.
  Future<VmMetrics> getVmMetrics(String name) async {
    final data = await _get('/vm/$name/metrics');
    return VmMetrics.fromJson(data);
  }

  /// POST /vm/<name>/start — Démarrer une VM.
  Future<Map<String, dynamic>> startVm(String name) async {
    return _post('/vm/$name/start');
  }

  /// POST /vm/<name>/stop — Arrêter une VM.
  Future<Map<String, dynamic>> stopVm(String name, {bool force = false}) async {
    return _post('/vm/$name/stop', body: {'force': force});
  }

  /// POST /vm/<name>/restart — Redémarrer une VM.
  Future<Map<String, dynamic>> restartVm(String name) async {
    return _post('/vm/$name/restart');
  }

  /// GET /stats/summary — Statistiques globales.
  Future<HostStats> getGlobalStats() async {
    final data = await _get('/stats/summary');
    return HostStats.fromJson(data);
  }
}
