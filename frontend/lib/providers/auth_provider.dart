import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final _storage = const FlutterSecureStorage();
  
  bool _isAuthenticated = false;
  String? _username;
  bool _isLoading = true;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get username => _username;

  AuthProvider(this._apiService) {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final token = await _storage.read(key: 'auth_token');
      final user = await _storage.read(key: 'username');
      
      if (token != null) {
        _apiService.setToken(token);
        _isAuthenticated = true;
        _username = user;
      } else {
        _isAuthenticated = false;
        _username = null;
      }
    } catch (e) {
      // En cas d'erreur de lecture (ex: première installation), on considère déconnecté
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final token = await _apiService.login(username, password);
      // Sauvegarder les infos
      await _storage.write(key: 'auth_token', value: token);
      await _storage.write(key: 'username', value: username);
      
      _isAuthenticated = true;
      _username = username;
    } catch (e) {
      _isAuthenticated = false;
      rethrow; 
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'username');
    _apiService.setToken(null);
    _isAuthenticated = false;
    _username = null;
    notifyListeners();
  }
}
