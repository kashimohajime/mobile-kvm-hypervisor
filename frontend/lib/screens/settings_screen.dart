/// Écran Paramètres — Configuration de l'API et préférences.
///
/// Permet de :
/// - Modifier l'IP du backend
/// - Tester la connexion
/// - Changer le thème (sombre/clair/système)
/// - Configurer l'auto-refresh
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _urlController = TextEditingController(text: settings.apiBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Teste la connexion au backend.
  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });

    try {
      final api = ApiService(
        baseUrl: _urlController.text.trim(),
        timeout: const Duration(seconds: 5),
        maxRetries: 0,
      );
      final health = await api.healthCheck();

      setState(() {
        _testSuccess = true;
        _testResult =
            'Connecté ! Libvirt ${health['libvirt']?['connected'] == true ? "OK" : "indisponible"}';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Échec de connexion : $e';
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Paramètres',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Section Connexion ────────────
              _buildSectionTitle('Connexion au backend', Icons.link_rounded,
                  colorScheme.primary, theme),
              const SizedBox(height: 12),
              _buildConnectionSection(settings, theme, colorScheme),

              const SizedBox(height: 32),

              // ── Section Apparence ────────────
              _buildSectionTitle('Apparence', Icons.palette_rounded,
                  colorScheme.tertiary, theme),
              const SizedBox(height: 12),
              _buildThemeSection(settings, theme, colorScheme),

              const SizedBox(height: 32),

              // ── Section Auto-refresh ─────────
              _buildSectionTitle('Auto-refresh', Icons.autorenew_rounded,
                  colorScheme.secondary, theme),
              const SizedBox(height: 12),
              _buildAutoRefreshSection(settings, theme, colorScheme),

              const SizedBox(height: 32),

              // ── Section À propos ─────────────
              _buildSectionTitle('À propos', Icons.info_outline_rounded,
                  colorScheme.outline, theme),
              const SizedBox(height: 12),
              _buildAboutSection(theme, colorScheme),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(
      String title, IconData icon, Color color, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  /// Section connexion : URL + test.
  Widget _buildConnectionSection(
    SettingsProvider settings,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'URL de l\'API',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withAlpha(150),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'http://192.168.1.100:5000',
              prefixIcon: const Icon(Icons.dns_outlined),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save_rounded),
                tooltip: 'Sauvegarder',
                onPressed: () async {
                  await settings.setApiBaseUrl(_urlController.text.trim());
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URL sauvegardée !')),
                    );
                  }
                },
              ),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),

          // Bouton test
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.speed_rounded),
              label: Text(_isTesting ? 'Test en cours...' : 'Tester la connexion'),
            ),
          ),

          // Résultat du test
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testSuccess!
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFEF5350))
                    .withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_testSuccess!
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFEF5350))
                      .withAlpha(60),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccess!
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    color: _testSuccess!
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFEF5350),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _testSuccess!
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFEF5350),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 50.ms);
  }

  /// Section thème.
  Widget _buildThemeSection(
    SettingsProvider settings,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _themeOption(
            'Système',
            Icons.brightness_auto_rounded,
            ThemeMode.system,
            settings,
            theme,
          ),
          _themeOption(
            'Clair',
            Icons.light_mode_rounded,
            ThemeMode.light,
            settings,
            theme,
          ),
          _themeOption(
            'Sombre',
            Icons.dark_mode_rounded,
            ThemeMode.dark,
            settings,
            theme,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }

  Widget _themeOption(
    String label,
    IconData icon,
    ThemeMode mode,
    SettingsProvider settings,
    ThemeData theme,
  ) {
    final isSelected = settings.themeMode == mode;

    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: settings.themeMode,
      onChanged: (value) {
        if (value != null) settings.setThemeMode(value);
      },
      title: Text(label),
      secondary: Icon(icon,
          color: isSelected ? theme.colorScheme.primary : null),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  /// Section auto-refresh.
  Widget _buildAutoRefreshSection(
    SettingsProvider settings,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Rafraîchissement automatique'),
            subtitle: Text(
                'Toutes les ${settings.refreshIntervalSeconds} secondes'),
            value: settings.autoRefresh,
            onChanged: (value) => settings.setAutoRefresh(value),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Intervalle : ${settings.refreshIntervalSeconds}s',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withAlpha(150),
            ),
          ),
          Slider(
            value: settings.refreshIntervalSeconds.toDouble(),
            min: 2,
            max: 30,
            divisions: 14,
            label: '${settings.refreshIntervalSeconds}s',
            onChanged: (value) {
              settings.setRefreshInterval(value.toInt());
            },
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 150.ms);
  }

  /// Section à propos.
  Widget _buildAboutSection(ThemeData theme, ColorScheme colorScheme) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.dns_rounded,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            title: const Text('KVM Supervisor'),
            subtitle: const Text('v1.0.0 — Supervision hyperviseur KVM'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Text(
            'Application de supervision de machines virtuelles KVM via une API REST Flask et libvirt.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withAlpha(120),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }
}
