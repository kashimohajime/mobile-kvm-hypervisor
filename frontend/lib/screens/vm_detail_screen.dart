/// Écran de détails d'une VM.
///
/// Affiche :
/// - Informations complètes (nom, état, UUID, OS, etc.)
/// - Métriques temps réel (jauges CPU et RAM)
/// - I/O disque et réseau
/// - Boutons d'action (Start, Stop, Restart)
/// - Graphique historique CPU/RAM (dernières valeurs)
library;

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../models/vm_model.dart';
import '../providers/vm_provider.dart';
import '../widgets/metric_widgets.dart';

class VmDetailScreen extends StatefulWidget {
  final String vmName;

  const VmDetailScreen({super.key, required this.vmName});

  @override
  State<VmDetailScreen> createState() => _VmDetailScreenState();
}

class _VmDetailScreenState extends State<VmDetailScreen> {
  Timer? _metricsTimer;
  bool _autoRefreshMetrics = false;

  // Historique des métriques pour les graphiques (max 20 points)
  final List<double> _cpuHistory = [];
  final List<double> _ramHistory = [];
  static const int _maxHistoryPoints = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VmProvider>().fetchVmDetails(widget.vmName);
    });
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    super.dispose();
  }

  /// Active/désactive le rafraîchissement automatique des métriques.
  void _toggleMetricsRefresh() {
    setState(() {
      _autoRefreshMetrics = !_autoRefreshMetrics;
    });

    if (_autoRefreshMetrics) {
      _metricsTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _refreshMetrics(),
      );
    } else {
      _metricsTimer?.cancel();
      _metricsTimer = null;
    }
  }

  Future<void> _refreshMetrics() async {
    final provider = context.read<VmProvider>();
    await provider.refreshVmMetrics(widget.vmName);

    final metrics = provider.selectedVmMetrics;
    if (metrics != null && mounted) {
      setState(() {
        _cpuHistory.add(metrics.cpuPercent);
        _ramHistory.add(metrics.memoryPercent);
        if (_cpuHistory.length > _maxHistoryPoints) _cpuHistory.removeAt(0);
        if (_ramHistory.length > _maxHistoryPoints) _ramHistory.removeAt(0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Consumer<VmProvider>(
        builder: (context, provider, _) {
          return CustomScrollView(
            slivers: [
              _buildAppBar(provider, theme, colorScheme),
              SliverToBoxAdapter(
                child: _buildContent(provider, theme, colorScheme),
              ),
            ],
          );
        },
      ),
    );
  }

  /// AppBar avec nom de la VM et badge d'état.
  SliverAppBar _buildAppBar(
    VmProvider provider,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final vm = provider.selectedVm;
    final stateColor = _getStateColor(vm?.state ?? '');

    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          widget.vmName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                stateColor.withAlpha(40),
                colorScheme.surface,
              ],
            ),
          ),
        ),
      ),
      actions: [
        // Toggle auto-refresh métriques
        IconButton(
          icon: Icon(
            _autoRefreshMetrics
                ? Icons.pause_circle_rounded
                : Icons.play_circle_rounded,
            color: _autoRefreshMetrics ? const Color(0xFF4CAF50) : null,
          ),
          tooltip: _autoRefreshMetrics
              ? 'Arrêter le suivi'
              : 'Suivi temps réel',
          onPressed: _toggleMetricsRefresh,
        ),
        // Rafraîchir manuellement
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Rafraîchir',
          onPressed: () => provider.fetchVmDetails(widget.vmName),
        ),
      ],
    );
  }

  /// Contenu principal : gère les états loading / error / data.
  Widget _buildContent(
    VmProvider provider,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    switch (provider.detailState) {
      case LoadingState.idle:
      case LoadingState.loading:
        return const Padding(
          padding: EdgeInsets.only(top: 100),
          child: Center(child: CircularProgressIndicator()),
        );

      case LoadingState.error:
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                const SizedBox(height: 60),
                Icon(Icons.error_outline_rounded,
                    size: 48, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(provider.detailError ?? 'Erreur inconnue'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => provider.fetchVmDetails(widget.vmName),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        );

      case LoadingState.loaded:
        final vm = provider.selectedVm;
        final metrics = provider.selectedVmMetrics;
        if (vm == null) return const SizedBox();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Actions ──────────────────────
              _buildActionButtons(vm, theme, colorScheme),
              const SizedBox(height: 20),

              // ── Jauges CPU & RAM ─────────────
              if (metrics != null && vm.isRunning)
                _buildGaugesRow(metrics, theme, colorScheme),

              if (metrics != null && vm.isRunning) const SizedBox(height: 20),

              // ── Graphique historique ──────────
              if (_cpuHistory.length > 1) ...[
                _buildMetricsChart(theme, colorScheme),
                const SizedBox(height: 20),
              ],

              // ── Infos détaillées ─────────────
              _buildInfoSection(vm, theme, colorScheme),
              const SizedBox(height: 20),

              // ── Disque I/O ───────────────────
              if (metrics != null &&
                  metrics.diskIo.isNotEmpty &&
                  vm.isRunning) ...[
                _buildDiskIoSection(metrics, theme, colorScheme),
                const SizedBox(height: 20),
              ],

              // ── Réseau I/O ───────────────────
              if (metrics != null &&
                  metrics.networkIo.isNotEmpty &&
                  vm.isRunning) ...[
                _buildNetworkIoSection(metrics, theme, colorScheme),
                const SizedBox(height: 20),
              ],

              const SizedBox(height: 40),
            ],
          ),
        );
    }
  }

  /// Boutons d'action : Start, Stop, Restart.
  Widget _buildActionButtons(
    VmModel vm,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        // START
        Expanded(
          child: _ActionButton(
            icon: Icons.play_arrow_rounded,
            label: 'Démarrer',
            color: const Color(0xFF4CAF50),
            enabled: !vm.isRunning,
            onPressed: () => _confirmAction(
              'Démarrer ${vm.name} ?',
              'La VM sera démarrée.',
              () => context.read<VmProvider>().startVm(vm.name),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // STOP
        Expanded(
          child: _ActionButton(
            icon: Icons.stop_rounded,
            label: 'Arrêter',
            color: const Color(0xFFEF5350),
            enabled: vm.isRunning,
            onPressed: () => _confirmAction(
              'Arrêter ${vm.name} ?',
              'La VM sera arrêtée proprement.',
              () => context.read<VmProvider>().stopVm(vm.name),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // RESTART
        Expanded(
          child: _ActionButton(
            icon: Icons.restart_alt_rounded,
            label: 'Redémarrer',
            color: const Color(0xFFFFA726),
            enabled: vm.isRunning,
            onPressed: () => _confirmAction(
              'Redémarrer ${vm.name} ?',
              'La VM sera redémarrée.',
              () => context.read<VmProvider>().restartVm(vm.name),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1);
  }

  /// Dialogue de confirmation avant action.
  void _confirmAction(
    String title,
    String message,
    Future<String> Function() action,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final msg = await action();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: const Color(0xFF4CAF50),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur : $e'),
                      backgroundColor: const Color(0xFFEF5350),
                    ),
                  );
                }
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  /// Jauges circulaires CPU et RAM côte à côte.
  Widget _buildGaugesRow(
    VmMetrics metrics,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildGaugeCard(
            'CPU',
            metrics.cpuPercent,
            colorScheme.primary,
            Icons.memory,
            '${metrics.vcpus ?? 0} vCPU',
            theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildGaugeCard(
            'RAM',
            metrics.memoryPercent,
            colorScheme.tertiary,
            Icons.storage_rounded,
            '${metrics.memoryUsedMb} / ${metrics.memoryTotalMb} Mo',
            theme,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildGaugeCard(
    String label,
    double percent,
    Color color,
    IconData icon,
    String subtitle,
    ThemeData theme,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(isDark ? 50 : 30)),
      ),
      child: Column(
        children: [
          CircularGauge(
            percent: percent,
            label: label,
            color: color,
            size: 90,
            strokeWidth: 7,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color.withAlpha(180)),
              const SizedBox(width: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Graphique historique CPU & RAM (fl_chart).
  Widget _buildMetricsChart(ThemeData theme, ColorScheme colorScheme) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withAlpha(isDark ? 50 : 30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded,
                  size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Historique',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _legendDot(colorScheme.primary, 'CPU'),
              const SizedBox(width: 12),
              _legendDot(colorScheme.tertiary, 'RAM'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawHorizontalLine: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: colorScheme.onSurface.withAlpha(20),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      interval: 25,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}%',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurface.withAlpha(100),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  _chartLine(_cpuHistory, colorScheme.primary),
                  _chartLine(_ramHistory, colorScheme.tertiary),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => colorScheme.surfaceContainerHigh,
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  LineChartBarData _chartLine(List<double> data, Color color) {
    return LineChartBarData(
      spots: List.generate(
        data.length,
        (i) => FlSpot(i.toDouble(), data[i].clamp(0, 100)),
      ),
      isCurved: true,
      curveSmoothness: 0.3,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withAlpha(30),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  /// Section informations détaillées.
  Widget _buildInfoSection(
    VmModel vm,
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
        border: Border.all(
          color: colorScheme.outline.withAlpha(isDark ? 30 : 20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Informations',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow('État', vm.state.toUpperCase(), theme,
              valueColor: _getStateColor(vm.state)),
          _infoRow('UUID', vm.uuid, theme),
          _infoRow('vCPUs', '${vm.vcpus}', theme),
          _infoRow('RAM', vm.formattedMemory, theme),
          _infoRow('Uptime', vm.formattedUptime, theme),
          if (vm.osType != null) _infoRow('Type OS', vm.osType!, theme),
          if (vm.autostart != null)
            _infoRow('Autostart', vm.autostart! ? 'Oui' : 'Non', theme),
          if (vm.isPersistent != null)
            _infoRow(
                'Persistante', vm.isPersistent! ? 'Oui' : 'Non', theme),
          if (vm.disks.isNotEmpty)
            _infoRow('Disques', vm.disks.join(', '), theme),
          if (vm.networkInterfaces.isNotEmpty)
            _infoRow('Interfaces', vm.networkInterfaces.join(', '), theme),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.05);
  }

  Widget _infoRow(String label, String value, ThemeData theme,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Section Disque I/O.
  Widget _buildDiskIoSection(
    VmMetrics metrics,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return _buildIoSection(
      title: 'Disque I/O',
      icon: Icons.disc_full_rounded,
      color: colorScheme.secondary,
      theme: theme,
      children: metrics.diskIo.map((disk) {
        return _ioTile(
          title: disk.device,
          items: [
            ('Lecture', DiskIo.formatBytes(disk.readBytes)),
            ('Écriture', DiskIo.formatBytes(disk.writeBytes)),
            ('Requêtes R', '${disk.readRequests}'),
            ('Requêtes W', '${disk.writeRequests}'),
          ],
          theme: theme,
        );
      }).toList(),
    );
  }

  /// Section Réseau I/O.
  Widget _buildNetworkIoSection(
    VmMetrics metrics,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return _buildIoSection(
      title: 'Réseau I/O',
      icon: Icons.wifi_rounded,
      color: colorScheme.tertiary,
      theme: theme,
      children: metrics.networkIo.map((net) {
        return _ioTile(
          title: net.interface_,
          items: [
            ('RX', DiskIo.formatBytes(net.rxBytes)),
            ('TX', DiskIo.formatBytes(net.txBytes)),
            ('Paquets RX', '${net.rxPackets}'),
            ('Paquets TX', '${net.txPackets}'),
          ],
          theme: theme,
        );
      }).toList(),
    );
  }

  Widget _buildIoSection({
    required String title,
    required IconData icon,
    required Color color,
    required ThemeData theme,
    required List<Widget> children,
  }) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(isDark ? 50 : 30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.05);
  }

  Widget _ioTile({
    required String title,
    required List<(String, String)> items,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: items.map((item) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.$1}: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
                Text(
                  item.$2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Couleur selon l'état de la VM.
  Color _getStateColor(String state) {
    switch (state) {
      case 'running':
        return const Color(0xFF4CAF50);
      case 'stopped':
      case 'shutoff':
        return const Color(0xFFEF5350);
      case 'paused':
        return const Color(0xFFFFA726);
      case 'crashed':
        return const Color(0xFFE53935);
      default:
        return const Color(0xFF9E9E9E);
    }
  }
}

/// Bouton d'action réutilisable (Start, Stop, Restart).
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: enabled
          ? color.withAlpha(isDark ? 40 : 25)
          : Colors.grey.withAlpha(isDark ? 20 : 15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(
                icon,
                color: enabled ? color : Colors.grey,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? color
                      : Colors.grey.withAlpha(150),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
