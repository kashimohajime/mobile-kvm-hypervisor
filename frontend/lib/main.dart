/// Point d'entrée de l'application KVM Supervisor.
///
/// Configure les providers, le thème Material Design 3
/// (mode sombre/clair) et le routage.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/vm_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/auth_provider.dart';
import 'services/api_service.dart';
import 'screens/vm_list_screen.dart';
import 'screens/vm_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Barre de statut transparente pour un look moderne
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const KvmSupervisorApp());
}

class KvmSupervisorApp extends StatelessWidget {
  const KvmSupervisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
        
        // ApiService : Singleton muté par SettingsProvider
        ProxyProvider<SettingsProvider, ApiService>(
          create: (_) => ApiService(baseUrl: 'http://192.168.1.100:5000'), // Default
          update: (_, settings, apiService) {
             apiService!.baseUrl = settings.apiBaseUrl;
             return apiService;
          },
        ),

        // AuthProvider : Dépend de ApiService
        ChangeNotifierProxyProvider<ApiService, AuthProvider>(
          create: (context) => AuthProvider(context.read<ApiService>()),
          update: (_, apiService, authProvider) => authProvider ?? AuthProvider(apiService),
        ),

        // VmProvider : Dépend de ApiService
        ChangeNotifierProxyProvider<ApiService, VmProvider>(
          create: (context) => VmProvider(context.read<ApiService>()),
          update: (_, apiService, vmProvider) => vmProvider ?? VmProvider(apiService),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'KVM Supervisor',
            debugShowCheckedModeBanner: false,

            // ── Thème clair ──────────────────────
            theme: _buildLightTheme(),

            // ── Thème sombre ─────────────────────
            darkTheme: _buildDarkTheme(),

            // ── Mode thème ───────────────────────
            themeMode: settings.themeMode,

            // ── Routes ───────────────────────────
            home: Consumer<AuthProvider>(
              builder: (context, auth, _) {
                if (auth.isLoading) {
                  return const Scaffold(
                      body: Center(child: CircularProgressIndicator()));
                }
                if (!auth.isAuthenticated) {
                  return const LoginScreen();
                }
                return const VmListScreen();
              },
            ),
            onGenerateRoute: (routeSettings) {
              switch (routeSettings.name) {
                case '/':
                  // Redirection vers home (géré par AuthProvider) ou VmListScreen si argument
                  return _buildPageRoute(const VmListScreen());
                case '/vm-detail':
                  final vmName = routeSettings.arguments as String;
                  return _buildPageRoute(VmDetailScreen(vmName: vmName));
                case '/settings':
                  return _buildPageRoute(const SettingsScreen());
                case '/dashboard':
                  return _buildPageRoute(const DashboardScreen());
                default:
                  return _buildPageRoute(const VmListScreen());
              }
            },
          );
        },
      ),
    );
  }

  /// Construit une route avec animation de transition fluide.
  PageRouteBuilder _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.03, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  /// Thème clair — Material Design 3
  ThemeData _buildLightTheme() {
    const seed = Color(0xFF6C63FF);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: colorScheme.surfaceContainerLow,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withAlpha(100),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }

  /// Thème sombre — Material Design 3
  ThemeData _buildDarkTheme() {
    const seed = Color(0xFF6C63FF);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: const Color(0xFF0F0F1A),
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: const Color(0xFF1A1A2E),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}
