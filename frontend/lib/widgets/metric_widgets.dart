/// Widgets réutilisables pour les jauges et métriques.
///
/// Inclut des jauges circulaires (CPU, RAM) et des cartes de métrique.
library;

import 'dart:math';
import 'package:flutter/material.dart';

/// Jauge circulaire animée pour afficher un pourcentage.
class CircularGauge extends StatelessWidget {
  final double percent;
  final String label;
  final Color color;
  final double size;
  final double strokeWidth;

  const CircularGauge({
    super.key,
    required this.percent,
    required this.label,
    required this.color,
    this.size = 100,
    this.strokeWidth = 8,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Fond du cercle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: strokeWidth,
              strokeCap: StrokeCap.round,
              color: color.withAlpha(30),
            ),
          ),
          // Jauge animée
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: strokeWidth,
                  strokeCap: StrokeCap.round,
                  color: _getColor(value * 100),
                ),
              );
            },
          ),
          // Texte central
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: percent),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Text(
                    '${value.toStringAsFixed(1)}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _getColor(value),
                    ),
                  );
                },
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(150),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Retourne une couleur selon le pourcentage (vert → orange → rouge).
  Color _getColor(double percent) {
    if (percent < 50) return color;
    if (percent < 80) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }
}

/// Carte de métrique avec icône, valeur et label.
class MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withAlpha(isDark ? 50 : 30),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withAlpha(isDark ? 40 : 25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const Spacer(),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
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
}

/// Barre de progression linéaire avec gradient et animation.
class GradientProgressBar extends StatelessWidget {
  final double percent; // 0-100
  final List<Color> colors;
  final double height;

  const GradientProgressBar({
    super.key,
    required this.percent,
    required this.colors,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0, 100)),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                // Background
                Container(
                  color: colors.first.withAlpha(30),
                ),
                // Progress
                FractionallySizedBox(
                  widthFactor: value / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Widget de chargement personnalisé (shimmer card).
class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade200;
    final highlightColor =
        isDark ? const Color(0xFF252540) : Colors.grey.shade100;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(16),
        height: 90,
        child: Row(
          children: [
            _shimmerBox(48, 48, baseColor, highlightColor, radius: 14),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _shimmerBox(double.infinity, 14, baseColor, highlightColor),
                  const SizedBox(height: 12),
                  _shimmerBox(150, 12, baseColor, highlightColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox(
    double width,
    double height,
    Color base,
    Color highlight, {
    double radius = 8,
  }) {
    return _ShimmerWidget(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Animation shimmer simple.
class _ShimmerWidget extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const _ShimmerWidget({
    required this.child,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<_ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<_ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: [
                max(0.0, _controller.value - 0.3),
                _controller.value,
                min(1.0, _controller.value + 0.3),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}
