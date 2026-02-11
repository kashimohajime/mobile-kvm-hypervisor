/// Provider pour les paramètres de l'application.
///
/// Gère la persistance de :
/// - L'URL du backend
/// - Le mode thème (sombre/clair/système)
/// - L'auto-refresh
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  // Clés de stockage
  static const _keyApiBaseUrl = 'api_base_url';
  static const _keyThemeMode = 'theme_mode';
  static const _keyAutoRefresh = 'auto_refresh';
  static const _keyRefreshInterval = 'refresh_interval';

  // Valeurs par défaut
  String _apiBaseUrl = 'http://192.168.1.100:5000';
  ThemeMode _themeMode = ThemeMode.dark;
  bool _autoRefresh = false;
  int _refreshIntervalSeconds = 5;

  // ── Getters ────────────────────────────────
  String get apiBaseUrl => _apiBaseUrl;
  ThemeMode get themeMode => _themeMode;
  bool get autoRefresh => _autoRefresh;
  int get refreshIntervalSeconds => _refreshIntervalSeconds;

  /// Charge les paramètres depuis le stockage local.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _apiBaseUrl = prefs.getString(_keyApiBaseUrl) ?? _apiBaseUrl;

    final themeIndex = prefs.getInt(_keyThemeMode);
    if (themeIndex != null && themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    }

    _autoRefresh = prefs.getBool(_keyAutoRefresh) ?? _autoRefresh;
    _refreshIntervalSeconds =
        prefs.getInt(_keyRefreshInterval) ?? _refreshIntervalSeconds;

    notifyListeners();
  }

  /// Met à jour l'URL du backend.
  Future<void> setApiBaseUrl(String url) async {
    // Nettoyer l'URL (enlever le / final si présent)
    _apiBaseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiBaseUrl, _apiBaseUrl);
    notifyListeners();
  }

  /// Change le mode thème.
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
    notifyListeners();
  }

  /// Active/désactive l'auto-refresh.
  Future<void> setAutoRefresh(bool enabled) async {
    _autoRefresh = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoRefresh, enabled);
    notifyListeners();
  }

  /// Change l'intervalle d'auto-refresh.
  Future<void> setRefreshInterval(int seconds) async {
    _refreshIntervalSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRefreshInterval, seconds);
    notifyListeners();
  }
}
