/// Widget réutilisable — Carte de VM pour la liste principale.
///
/// Affiche : nom, état (badge coloré), CPU%, RAM%, icône d'état.
/// Supporte le tap pour naviguer vers les détails.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/vm_model.dart';

class VmCard extends StatelessWidget {
  final VmModel vm;
  final VoidCallback onTap;
  final int animationIndex;

  const VmCard({
    super.key,
    required this.vm,
    required this.onTap,
    this.animationIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _stateColor.withAlpha(isDark ? 60 : 40),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // ── Icône d'état ────────────────────
              _buildStateIcon(isDark),
              const SizedBox(width: 16),

              // ── Infos principales ──────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nom + Badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vm.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStateBadge(colorScheme),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Métriques rapides
                    Row(
                      children: [
                        _buildMetricChip(
                          icon: Icons.memory,
                          label: '${vm.vcpus} vCPU',
                          color: colorScheme.primary,
                          theme: theme,
                        ),
                        const SizedBox(width: 12),
                        _buildMetricChip(
                          icon: Icons.storage_rounded,
                          label: vm.formattedMemory,
                          color: colorScheme.tertiary,
                          theme: theme,
                        ),
                        if (vm.uptimeSeconds != null &&
                            vm.uptimeSeconds! > 0) ...[
                          const SizedBox(width: 12),
                          _buildMetricChip(
                            icon: Icons.timer_outlined,
                            label: vm.formattedUptime,
                            color: colorScheme.secondary,
                            theme: theme,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Chevron ────────────────────────
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurface.withAlpha(100),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          duration: 400.ms,
          delay: Duration(milliseconds: 50 * animationIndex),
        )
        .slideX(
          begin: 0.05,
          end: 0,
          duration: 400.ms,
          delay: Duration(milliseconds: 50 * animationIndex),
          curve: Curves.easeOut,
        );
  }

  /// Icône circulaire colorée selon l'état.
  Widget _buildStateIcon(bool isDark) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _stateColor.withAlpha(isDark ? 40 : 30),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        _stateIcon,
        color: _stateColor,
        size: 24,
      ),
    );
  }

  /// Badge d'état (running / stopped / etc.)
  Widget _buildStateBadge(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _stateColor.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _stateColor.withAlpha(80), width: 1),
      ),
      child: Text(
        _stateLabel,
        style: TextStyle(
          color: _stateColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Petit chip de métrique.
  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required Color color,
    required ThemeData theme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color.withAlpha(180)),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(180),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Helpers visuels selon l'état ───────────

  Color get _stateColor {
    switch (vm.state) {
      case 'running':
        return const Color(0xFF4CAF50); // vert
      case 'stopped':
      case 'shutoff':
        return const Color(0xFFEF5350); // rouge
      case 'paused':
        return const Color(0xFFFFA726); // orange
      case 'crashed':
        return const Color(0xFFE53935); // rouge foncé
      case 'suspended':
        return const Color(0xFF42A5F5); // bleu
      default:
        return const Color(0xFF9E9E9E); // gris
    }
  }

  IconData get _stateIcon {
    switch (vm.state) {
      case 'running':
        return Icons.play_circle_rounded;
      case 'stopped':
      case 'shutoff':
        return Icons.stop_circle_rounded;
      case 'paused':
        return Icons.pause_circle_rounded;
      case 'crashed':
        return Icons.error_rounded;
      case 'suspended':
        return Icons.nights_stay_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String get _stateLabel {
    switch (vm.state) {
      case 'running':
        return 'EN MARCHE';
      case 'stopped':
      case 'shutoff':
        return 'ARRÊTÉE';
      case 'paused':
        return 'EN PAUSE';
      case 'crashed':
        return 'CRASHÉE';
      case 'suspended':
        return 'SUSPENDUE';
      default:
        return vm.state.toUpperCase();
    }
  }
}
