/// Écran Dashboard — Vue globale de l'hyperviseur.
///
/// Affiche :
/// - Infos de l'hôte (hostname, CPU, RAM, libvirt)
/// - Compteurs de VMs (total, actives, inactives)
/// - Répartition par état (diagramme circulaire)
/// - Liste compacte des VMs
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../models/vm_model.dart';
import '../providers/vm_provider.dart';
import '../widgets/metric_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VmProvider>().fetchGlobalStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Dashboard',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<VmProvider>().fetchGlobalStats(),
          ),
        ],
      ),
      body: Consumer<VmProvider>(
        builder: (context, provider, _) {
          switch (provider.statsState) {
            case LoadingState.idle:
            case LoadingState.loading:
              return const Center(child: CircularProgressIndicator());

            case LoadingState.error:
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48,
                        color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(provider.statsError ?? 'Erreur'),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => provider.fetchGlobalStats(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              );

            case LoadingState.loaded:
              final stats = provider.hostStats;
              if (stats == null) return const SizedBox();

              return RefreshIndicator(
                onRefresh: () => provider.fetchGlobalStats(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHostCard(stats.host, theme, colorScheme),
                    const SizedBox(height: 16),
                    _buildVmCounters(stats, theme, colorScheme),
                    const SizedBox(height: 16),
                    if (stats.stateDistribution.isNotEmpty) ...[
                      _buildPieChart(stats, theme, colorScheme),
                      const SizedBox(height: 16),
                    ],
                    _buildVmTable(stats.vms, theme, colorScheme),
                    const SizedBox(height: 40),
                  ],
                ),
              );
          }
        },
      ),
    );
  }

  /// Carte informations de l'hôte.
  Widget _buildHostCard(
    HostInfo host,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withAlpha(isDark ? 80 : 120),
            colorScheme.tertiaryContainer.withAlpha(isDark ? 60 : 80),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withAlpha(isDark ? 40 : 30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.dns_rounded, color: colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.hostname,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${host.hypervisorType} — libvirt ${host.libvirtVersion}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  icon: Icons.memory,
                  label: 'CPU',
                  value: '${host.cpus} cœurs',
                  subtitle: host.cpuModel,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricTile(
                  icon: Icons.storage_rounded,
                  label: 'RAM',
                  value: host.formattedMemory,
                  subtitle: '${host.cpuFrequencyMhz} MHz',
                  color: colorScheme.tertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  /// Compteurs : Total / Actives / Inactives.
  Widget _buildVmCounters(
    HostStats stats,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Expanded(
          child: _counterCard(
            '${stats.vmsTotal}',
            'Total',
            Icons.apps_rounded,
            colorScheme.primary,
            theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _counterCard(
            '${stats.vmsActive}',
            'Actives',
            Icons.play_circle_rounded,
            const Color(0xFF4CAF50),
            theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _counterCard(
            '${stats.vmsInactive}',
            'Arrêtées',
            Icons.stop_circle_rounded,
            const Color(0xFFEF5350),
            theme,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1);
  }

  Widget _counterCard(
    String count,
    String label,
    IconData icon,
    Color color,
    ThemeData theme,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(isDark ? 50 : 30)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            count,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(150),
            ),
          ),
        ],
      ),
    );
  }

  /// Diagramme circulaire de répartition des états.
  Widget _buildPieChart(
    HostStats stats,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    final stateColors = {
      'running': const Color(0xFF4CAF50),
      'stopped': const Color(0xFFEF5350),
      'paused': const Color(0xFFFFA726),
      'crashed': const Color(0xFFE53935),
      'suspended': const Color(0xFF42A5F5),
    };

    final sections = stats.stateDistribution.entries.map((entry) {
      final color = stateColors[entry.key] ?? Colors.grey;
      return PieChartSectionData(
        value: entry.value.toDouble(),
        title: '${entry.value}',
        color: color,
        radius: 50,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      );
    }).toList();

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
            'Répartition par état',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: Row(
              children: [
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 35,
                      sectionsSpace: 3,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: stats.stateDistribution.entries.map((entry) {
                    final color =
                        stateColors[entry.key] ?? Colors.grey;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${entry.key} (${entry.value})',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }

  /// Tableau compact des VMs.
  Widget _buildVmTable(
    List<VmModel> vms,
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
            'Machines virtuelles',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...vms.map((vm) {
            final stateColor = _getStateColor(vm.state);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(vm.name,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(
                '${vm.vcpus} vCPU • ${vm.formattedMemory}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withAlpha(120),
                ),
              ),
              trailing: Text(
                vm.state,
                style: TextStyle(
                  color: stateColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.pushNamed(context, '/vm-detail', arguments: vm.name);
              },
            );
          }),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
  }

  Color _getStateColor(String state) {
    switch (state) {
      case 'running':
        return const Color(0xFF4CAF50);
      case 'stopped':
      case 'shutoff':
        return const Color(0xFFEF5350);
      case 'paused':
        return const Color(0xFFFFA726);
      default:
        return const Color(0xFF9E9E9E);
    }
  }
}
