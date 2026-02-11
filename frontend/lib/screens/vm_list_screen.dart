/// Écran principal — Liste des machines virtuelles.
///
/// Fonctionnalités :
/// - Liste des VMs sous forme de cartes
/// - Pull-to-refresh
/// - Barre de recherche
/// - Filtrage par état
/// - Bouton flottant pour auto-refresh
/// - Navigation vers détails et dashboard
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../providers/vm_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/vm_card.dart';
import '../widgets/metric_widgets.dart';

class VmListScreen extends StatefulWidget {
  const VmListScreen({super.key});

  @override
  State<VmListScreen> createState() => _VmListScreenState();
}

class _VmListScreenState extends State<VmListScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    // Charger les VMs au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VmProvider>().fetchVms();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildAppBar(theme, colorScheme, innerBoxIsScrolled),
        ],
        body: Consumer<VmProvider>(
          builder: (context, provider, _) {
            return _buildBody(provider, theme, colorScheme);
          },
        ),
      ),
      floatingActionButton: _buildFab(colorScheme),
    );
  }

  /// AppBar avec recherche et actions.
  SliverAppBar _buildAppBar(
    ThemeData theme,
    ColorScheme colorScheme,
    bool innerBoxIsScrolled,
  ) {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: true,
      expandedHeight: _showSearch ? 130 : 70,
      title: _showSearch
          ? null
          : Text(
              'KVM Supervisor',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
      flexibleSpace: _showSearch
          ? FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(16, 80, 16, 0),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Rechercher une VM...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        context.read<VmProvider>().setSearchQuery('');
                        setState(() => _showSearch = false);
                      },
                    ),
                  ),
                  onChanged: (value) {
                    context.read<VmProvider>().setSearchQuery(value);
                  },
                ),
              ),
            )
          : null,
      actions: [
        if (!_showSearch)
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Rechercher',
            onPressed: () => setState(() => _showSearch = true),
          ),
        IconButton(
          icon: const Icon(Icons.dashboard_rounded),
          tooltip: 'Dashboard',
          onPressed: () => Navigator.pushNamed(context, '/dashboard'),
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'Paramètres',
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ],
    );
  }

  /// Corps principal : gère loading / error / empty / data.
  Widget _buildBody(
    VmProvider provider,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    switch (provider.vmsState) {
      case LoadingState.idle:
      case LoadingState.loading:
        return _buildLoading();

      case LoadingState.error:
        return _buildError(provider, theme, colorScheme);

      case LoadingState.loaded:
        if (provider.vms.isEmpty) {
          return _buildEmpty(provider, theme, colorScheme);
        }
        return _buildVmList(provider, theme, colorScheme);
    }
  }

  /// Affichage pendant le chargement (shimmer).
  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: 5,
      itemBuilder: (_, __) => const ShimmerCard(),
    );
  }

  /// Affichage en cas d'erreur.
  Widget _buildError(
    VmProvider provider,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Connexion impossible',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.vmsError ?? 'Erreur inconnue',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => provider.fetchVms(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Vérifier les paramètres'),
            ),
          ],
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .scale(begin: const Offset(0.95, 0.95), duration: 400.ms),
      ),
    );
  }

  /// Affichage vide (aucune VM).
  Widget _buildEmpty(
    VmProvider provider,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final hasFilter =
        provider.searchQuery.isNotEmpty || provider.stateFilter != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter
                  ? Icons.search_off_rounded
                  : Icons.dns_outlined,
              size: 64,
              color: colorScheme.onSurface.withAlpha(80),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter
                  ? 'Aucune VM trouvée'
                  : 'Aucune machine virtuelle',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withAlpha(150),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Modifiez vos critères de recherche'
                  : 'Créez des VMs sur votre hyperviseur KVM',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withAlpha(100),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => provider.fetchVms(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Rafraîchir'),
            ),
          ],
        ),
      ),
    );
  }

  /// Liste des VMs avec résumé en tête et filtres.
  Widget _buildVmList(
    VmProvider provider,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return RefreshIndicator(
      onRefresh: () => provider.fetchVms(),
      color: colorScheme.primary,
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 100),
        children: [
          // ── Résumé rapide ────────────────────
          _buildQuickSummary(provider, theme, colorScheme),

          // ── Filtres par état ─────────────────
          _buildStateFilters(provider, colorScheme),

          const SizedBox(height: 4),

          // ── Cartes VM ────────────────────────
          ...List.generate(provider.vms.length, (index) {
            final vm = provider.vms[index];
            return VmCard(
              vm: vm,
              animationIndex: index,
              onTap: () {
                Navigator.pushNamed(context, '/vm-detail', arguments: vm.name);
              },
            );
          }),
        ],
      ),
    );
  }

  /// Résumé rapide : total / running / stopped.
  Widget _buildQuickSummary(
    VmProvider provider,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildCountChip(
            '${provider.totalVms}',
            'Total',
            colorScheme.primary,
            colorScheme,
          ),
          const SizedBox(width: 8),
          _buildCountChip(
            '${provider.runningVms}',
            'Actives',
            const Color(0xFF4CAF50),
            colorScheme,
          ),
          const SizedBox(width: 8),
          _buildCountChip(
            '${provider.stoppedVms}',
            'Arrêtées',
            const Color(0xFFEF5350),
            colorScheme,
          ),
          const Spacer(),
          // Indicateur auto-refresh
          if (provider.autoRefreshActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: const Color(0xFF4CAF50),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .shimmer(duration: 2000.ms, color: const Color(0xFF4CAF50).withAlpha(50)),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  /// Chip de compteur.
  Widget _buildCountChip(
    String count,
    String label,
    Color color,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color.withAlpha(180),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Filtres horizontaux par état.
  Widget _buildStateFilters(VmProvider provider, ColorScheme colorScheme) {
    final filters = [
      (null, 'Toutes', Icons.apps_rounded),
      ('running', 'Actives', Icons.play_circle_rounded),
      ('stopped', 'Arrêtées', Icons.stop_circle_rounded),
      ('paused', 'En pause', Icons.pause_circle_rounded),
    ];

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final (filterState, label, icon) = filters[index];
          final isSelected = provider.stateFilter == filterState;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(label),
              avatar: Icon(icon, size: 16),
              selected: isSelected,
              onSelected: (_) {
                provider.setStateFilter(isSelected ? null : filterState);
              },
              showCheckmark: false,
              selectedColor: colorScheme.primaryContainer,
            ),
          );
        },
      ),
    );
  }

  /// Bouton flottant : toggle auto-refresh.
  Widget _buildFab(ColorScheme colorScheme) {
    return Consumer<VmProvider>(
      builder: (context, provider, _) {
        final settings = context.read<SettingsProvider>();
        final isActive = provider.autoRefreshActive;

        return FloatingActionButton.extended(
          onPressed: () {
            provider.toggleAutoRefresh(
              intervalSeconds: settings.refreshIntervalSeconds,
            );

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isActive
                      ? 'Auto-refresh désactivé'
                      : 'Auto-refresh activé (${settings.refreshIntervalSeconds}s)',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          icon: Icon(
            isActive ? Icons.pause_rounded : Icons.autorenew_rounded,
          ),
          label: Text(isActive ? 'Pause' : 'Auto'),
          backgroundColor: isActive
              ? const Color(0xFF4CAF50)
              : colorScheme.primaryContainer,
          foregroundColor: isActive
              ? Colors.white
              : colorScheme.onPrimaryContainer,
        )
            .animate(target: isActive ? 1 : 0)
            .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.05, 1.05),
              duration: 800.ms,
              curve: Curves.easeInOut,
            );
      },
    );
  }
}
