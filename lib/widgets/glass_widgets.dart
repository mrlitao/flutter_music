import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:material_ui/material_ui.dart';

/// Frosted Glass (毛玻璃) container with Gaussian blur, specular border highlight, and subtle tint.
class AuraGlassContainer extends StatelessWidget {
  const AuraGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20.0,
    this.blurSigma = 22.0,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.tintColor,
    this.borderColor,
    this.isLightMode = false,
    this.onTap,
  });

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? tintColor;
  final Color? borderColor;
  final bool isLightMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final effectiveTint = tintColor ??
        (isLightMode
            ? Colors.white.withValues(alpha: 0.58)
            : Colors.white.withValues(alpha: 0.08));
    final effectiveBorder = borderColor ??
        (isLightMode
            ? Colors.white.withValues(alpha: 0.75)
            : Colors.white.withValues(alpha: 0.16));

    Widget content = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: effectiveTint,
            border: Border.all(color: effectiveBorder, width: 1.0),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLightMode
                  ? [
                      Colors.white.withValues(alpha: 0.72),
                      Colors.white.withValues(alpha: 0.42),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.13),
                      Colors.white.withValues(alpha: 0.04),
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLightMode ? 0.06 : 0.28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      content = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}

/// Fullscreen dynamic Aurora background that smoothly blends the active track's palette
/// and subtly breathes with the music's bass energy.
class DynamicAuroraBackground extends StatelessWidget {
  const DynamicAuroraBackground({
    super.key,
    required this.colors,
    required this.phase,
    required this.bassEnergy,
    required this.isLightMode,
    required this.child,
  });

  final List<Color> colors;
  final double phase;
  final double bassEnergy;
  final bool isLightMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c1 = colors.isNotEmpty ? colors[0] : const Color(0xFF06B6D4);
    final c2 = colors.length > 1 ? colors[1] : const Color(0xFFD946EF);
    final c3 = colors.length > 2 ? colors[2] : const Color(0xFF6366F1);

    final baseBg = isLightMode ? const Color(0xFFEEF2FF) : const Color(0xFF060913);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base deep/light canvas
        ColoredBox(color: baseBg),
        // Animated Aurora gradient mesh painter
        RepaintBoundary(
          child: CustomPaint(
            painter: _AuroraMeshPainter(
              c1: c1,
              c2: c2,
              c3: c3,
              phase: phase,
              bassEnergy: bassEnergy,
              isLightMode: isLightMode,
            ),
          ),
        ),
        // Frosted diffusion veil
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
          child: ColoredBox(
            color: isLightMode
                ? Colors.white.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.22),
          ),
        ),
        child,
      ],
    );
  }
}

class _AuroraMeshPainter extends CustomPainter {
  const _AuroraMeshPainter({
    required this.c1,
    required this.c2,
    required this.c3,
    required this.phase,
    required this.bassEnergy,
    required this.isLightMode,
  });

  final Color c1;
  final Color c2;
  final Color c3;
  final double phase;
  final double bassEnergy;
  final bool isLightMode;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double shortest = math.min(w, h);
    final double alphaScale = isLightMode ? 0.35 : 0.44;
    final double pulse = 1.0 + bassEnergy * 0.22;

    // Orb 1 (Top-Left drifting)
    final Offset center1 = Offset(
      w * (0.22 + 0.12 * math.sin(phase * 0.25)),
      h * (0.25 + 0.10 * math.cos(phase * 0.20)),
    );
    _drawGlowOrb(canvas, center1, shortest * 0.58 * pulse, c1.withValues(alpha: alphaScale));

    // Orb 2 (Bottom-Right drifting)
    final Offset center2 = Offset(
      w * (0.78 - 0.12 * math.cos(phase * 0.22)),
      h * (0.74 - 0.10 * math.sin(phase * 0.28)),
    );
    _drawGlowOrb(canvas, center2, shortest * 0.62 * pulse, c2.withValues(alpha: alphaScale));

    // Orb 3 (Center-Right harmonic drift)
    final Offset center3 = Offset(
      w * (0.52 + 0.16 * math.cos(phase * 0.18 + 1.2)),
      h * (0.48 + 0.14 * math.sin(phase * 0.24 + 0.8)),
    );
    _drawGlowOrb(canvas, center3, shortest * 0.50 * pulse, c3.withValues(alpha: alphaScale * 0.85));
  }

  void _drawGlowOrb(Canvas canvas, Offset center, double radius, Color color) {
    if (radius <= 1) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color,
          color.withValues(alpha: color.a * 0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _AuroraMeshPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.bassEnergy != bassEnergy ||
        oldDelegate.c1 != c1 ||
        oldDelegate.c2 != c2 ||
        oldDelegate.isLightMode != isLightMode;
  }
}

/// Renders either the track's embedded album cover bytes or a stylized holographic vinyl art.
class AlbumCoverAvatar extends StatelessWidget {
  const AlbumCoverAvatar({
    super.key,
    required this.coverBytes,
    required this.colors,
    this.size = 48.0,
    this.borderRadius = 12.0,
    this.isCircular = false,
  });

  final Uint8List? coverBytes;
  final List<Color> colors;
  final double size;
  final double borderRadius;
  final bool isCircular;

  @override
  Widget build(BuildContext context) {
    final c1 = colors.isNotEmpty ? colors[0] : const Color(0xFF06B6D4);
    final c2 = colors.length > 1 ? colors[1] : const Color(0xFFD946EF);
    final c3 = colors.length > 2 ? colors[2] : const Color(0xFF6366F1);

    Widget inner;
    if (coverBytes != null && coverBytes!.isNotEmpty) {
      inner = Image.memory(
        coverBytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackArtwork(c1, c2, c3),
      );
    } else {
      inner = _buildFallbackArtwork(c1, c2, c3);
    }

    if (isCircular) {
      return ClipOval(child: SizedBox(width: size, height: size, child: inner));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: size, height: size, child: inner),
    );
  }

  Widget _buildFallbackArtwork(Color c1, Color c2, Color c3) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: SweepGradient(
          colors: [c1, c2, c3, c1],
        ),
      ),
      child: Center(
        child: Container(
          width: size * 0.72,
          height: size * 0.72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.42),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.2),
          ),
          child: Center(
            child: Icon(
              Icons.music_note_rounded,
              size: size * 0.36,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}
