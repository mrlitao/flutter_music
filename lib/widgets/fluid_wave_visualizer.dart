import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../models/track.dart';
import 'glass_widgets.dart';

/// Audio-Reactive Fluid Streamline Wave Ripple Visualizer (流线波纹随音乐旋律与音律跳动).
/// Maps the 32 real-time FFT melody/rhythm frequency bins directly onto smooth cubic-interpolated
/// polar wave lobes so every vocal note, instrument chord, and drum beat visibly leaps in real time.
class FluidWaveRippleVisualizer extends StatelessWidget {
  const FluidWaveRippleVisualizer({
    super.key,
    required this.track,
    required this.spectrum,
    required this.colors,
    required this.isPlaying,
    this.size = 310.0,
    this.onTapCenter,
  });

  final Track track;
  final SpectrumFrame spectrum;
  final List<Color> colors;
  final bool isPlaying;
  final double size;
  final VoidCallback? onTapCenter;

  @override
  Widget build(BuildContext context) {
    final double discBaseSize = size * 0.41;
    final double bassScale =
        1.0 + (isPlaying ? (spectrum.beatPulse * 0.10 + spectrum.bassEnergy * 0.04) : 0.0);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTapCenter,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Multi-layer Melody-Driven Fluid Streamline Wave Ripple Canvas
              CustomPaint(
                size: Size(size, size),
                painter: FluidWaveRipplePainter(
                  spectrum: spectrum,
                  colors: colors,
                  isPlaying: isPlaying,
                ),
              ),

              // 2. Central Rotating Vinyl & Album Cover with Bass Beat Pulse
              Transform.scale(
                scale: bassScale,
                child: Transform.rotate(
                  angle: spectrum.phase * 0.14,
                  child: Container(
                    width: discBaseSize,
                    height: discBaseSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (colors.isNotEmpty ? colors[0] : const Color(0xFF06B6D4))
                              .withValues(alpha: 0.32 + spectrum.bassEnergy * 0.42),
                          blurRadius: 24 + spectrum.beatPulse * 24,
                          spreadRadius: 2 + spectrum.beatPulse * 6,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.42 + spectrum.beatPulse * 0.35),
                        width: 2.2,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AlbumCoverAvatar(
                          coverBytes: track.coverBytes,
                          colors: colors,
                          size: discBaseSize,
                          isCircular: true,
                        ),
                        Container(
                          width: discBaseSize * 0.82,
                          height: discBaseSize * 0.82,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1.0,
                            ),
                          ),
                        ),
                        Container(
                          width: discBaseSize * 0.18,
                          height: discBaseSize * 0.18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF090D16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                              width: 2.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CustomPainter that directly couples the 32 FFT frequency bins (Bass, Vocal/Melody Mid, Treble)
/// into smooth polar streamline wave crests with fast transient response.
class FluidWaveRipplePainter extends CustomPainter {
  const FluidWaveRipplePainter({
    required this.spectrum,
    required this.colors,
    required this.isPlaying,
  });

  final SpectrumFrame spectrum;
  final List<Color> colors;
  final bool isPlaying;

  /// Smooth cosine-interpolated lookup across [bins] at normalized angle [normAngle] (0.0 .. 1.0).
  /// Mirrors 0..0.5 and 0.5..1.0 so the 360° closed ring has zero seam discontinuity.
  double _sampleSmoothBin(
    List<double> bins,
    double normAngle, {
    required int startBin,
    required int endBin,
  }) {
    if (bins.isEmpty) return 0.03;
    final double wrapped = normAngle - normAngle.floorToDouble();
    final double mirrored = wrapped <= 0.5 ? (wrapped * 2.0) : ((1.0 - wrapped) * 2.0);

    final int s = startBin.clamp(0, bins.length - 1);
    final int e = endBin.clamp(s + 1, bins.length);
    final int span = math.max(1, e - s - 1);

    final double exactPos = s + mirrored * span;
    final int idx0 = exactPos.floor().clamp(s, e - 1);
    final int idx1 = (idx0 + 1).clamp(s, e - 1);
    final int idxPrev = (idx0 - 1).clamp(s, e - 1);
    final int idxNext = (idx1 + 1).clamp(s, e - 1);

    final double frac = exactPos - idx0;
    // Cosine interpolation blended with neighbor smoothing for liquid streamline peaks
    final double mu = (1.0 - math.cos(frac * math.pi)) * 0.5;
    final double v0 = bins[idxPrev] * 0.2 + bins[idx0] * 0.8;
    final double v1 = bins[idx1] * 0.8 + bins[idxNext] * 0.2;
    return v0 + (v1 - v0) * mu;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxRadius = math.min(size.width, size.height) / 2;
    final double baseDiscRadius = maxRadius * 0.42;

    final Color c1 = colors.isNotEmpty ? colors[0] : const Color(0xFF06B6D4);
    final Color c2 = colors.length > 1 ? colors[1] : const Color(0xFFD946EF);
    final Color c3 = colors.length > 2 ? colors[2] : const Color(0xFF6366F1);

    final double bass = spectrum.bassEnergy;
    final double mid = spectrum.midEnergy;
    final double treble = spectrum.trebleEnergy;
    final double beat = spectrum.beatPulse;
    final double phase = spectrum.phase;
    final List<double> bins = spectrum.bins;

    // 1. Dynamic Radial Aura Glow pulsing with Bass & Melody Energy
    final Rect auraRect = Rect.fromCircle(center: center, radius: maxRadius * 0.98);
    final Paint auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          c1.withValues(alpha: (0.18 + bass * 0.32 + beat * 0.15).clamp(0.1, 0.7)),
          c2.withValues(alpha: (0.10 + mid * 0.25).clamp(0.05, 0.5)),
          Colors.transparent,
        ],
        stops: const [0.34, 0.74, 1.0],
      ).createShader(auraRect);
    canvas.drawCircle(center, maxRadius * 0.98, auraPaint);

    // 2. 5 Melodic & Rhythmic Streamline Wave Layers
    // Each layer focuses on a specific frequency range of the playing song (Bass, Vocal/Lead Melody, Harmonic Overtone, Treble)
    final layers = <_MelodyWaveLayer>[
      // Layer 0: Inner Bass & Beat Drive Ring (bins 0..10)
      _MelodyWaveLayer(
        color: c1,
        baseOffset: maxRadius * 0.035,
        maxJump: maxRadius * 0.24,
        startBin: 0,
        endBin: 12,
        harmonicLobes: 4,
        angularDrift: phase * 0.08,
        strokeWidth: 2.8,
        glowSigma: 9.0,
        alpha: 0.92,
        fillAlpha: 0.10,
        beatWeight: 1.0,
      ),
      // Layer 1: Primary Vocal & Lead Melody Streamline (bins 5..20)
      _MelodyWaveLayer(
        color: c2,
        baseOffset: maxRadius * 0.09,
        maxJump: maxRadius * 0.30,
        startBin: 5,
        endBin: 21,
        harmonicLobes: 6,
        angularDrift: -phase * 0.11 + 0.35,
        strokeWidth: 2.3,
        glowSigma: 8.0,
        alpha: 0.84,
        fillAlpha: 0.07,
        beatWeight: 0.65,
      ),
      // Layer 2: Counter-Flowing Harmonic Melody Ribbon (bins 8..25)
      _MelodyWaveLayer(
        color: c3,
        baseOffset: maxRadius * 0.145,
        maxJump: maxRadius * 0.28,
        startBin: 8,
        endBin: 26,
        harmonicLobes: 8,
        angularDrift: phase * 0.14 + 0.72,
        strokeWidth: 2.0,
        glowSigma: 6.5,
        alpha: 0.74,
        fillAlpha: 0.05,
        beatWeight: 0.45,
      ),
      // Layer 3: High-Mid & Treble Shimmer Streamline (bins 14..31)
      _MelodyWaveLayer(
        color: Color.lerp(c1, c2, 0.5) ?? c1,
        baseOffset: maxRadius * 0.20,
        maxJump: maxRadius * 0.25,
        startBin: 14,
        endBin: 32,
        harmonicLobes: 10,
        angularDrift: -phase * 0.09 + 1.15,
        strokeWidth: 1.6,
        glowSigma: 5.5,
        alpha: 0.60,
        fillAlpha: 0.03,
        beatWeight: 0.35,
      ),
      // Layer 4: Outer Full-Spectrum Acoustic Halo (bins 0..31)
      _MelodyWaveLayer(
        color: Color.lerp(c2, Colors.white, 0.38) ?? c2,
        baseOffset: maxRadius * 0.25,
        maxJump: maxRadius * 0.22,
        startBin: 0,
        endBin: 32,
        harmonicLobes: 12,
        angularDrift: phase * 0.06 + 1.6,
        strokeWidth: 1.25,
        glowSigma: 4.5,
        alpha: 0.45,
        fillAlpha: 0.0,
        beatWeight: 0.80,
      ),
    ];

    const int segments = 160;

    for (int l = 0; l < layers.length; l++) {
      final spec = layers[l];
      final Path path = Path();

      for (int i = 0; i <= segments; i++) {
        final double norm = i / segments;
        final double theta = norm * math.pi * 2.0;

        // Direct smooth frequency bin energy at this angle!
        final double binEnergy = _sampleSmoothBin(
          bins,
          norm + spec.angularDrift / (math.pi * 2.0),
          startBin: spec.startBin,
          endBin: spec.endBin,
        );

        // Subtract baseline idle floor so quiet moments rest calmly and melody peaks leap!
        final double activeSignal = math.max(0.0, binEnergy - 0.03);

        // Organic fluid carrier modulation so the frequency lobes weave like liquid silk
        final double carrier1 =
            0.55 + 0.45 * math.sin(theta * spec.harmonicLobes + spec.angularDrift * 2.2);
        final double carrier2 =
            0.50 + 0.50 * math.cos(theta * (spec.harmonicLobes + 3) - spec.angularDrift * 1.7);
        final double fluidEnvelope = (carrier1 * 0.62 + carrier2 * 0.38);

        // When paused, keep only a tiny 2px breathing ripple; when playing, leap proportionally to activeSignal!
        final double melodyJump = isPlaying
            ? (activeSignal * (0.45 + fluidEnvelope * 0.85) * spec.maxJump)
            : (math.sin(theta * 4 + phase + l) * 1.8);

        final double beatExpansion =
            isPlaying ? (beat * spec.beatWeight * maxRadius * 0.075) : 0.0;

        final double r = baseDiscRadius + spec.baseOffset + beatExpansion + melodyJump;
        final double x = center.dx + math.cos(theta) * r;
        final double y = center.dy + math.sin(theta) * r;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();

      if (spec.fillAlpha > 0) {
        final Paint fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = spec.color.withValues(alpha: spec.fillAlpha);
        canvas.drawPath(path, fillPaint);
      }

      final Paint glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.strokeWidth * 2.3
        ..color = spec.color.withValues(alpha: spec.alpha * 0.44)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, spec.glowSigma);
      canvas.drawPath(path, glowPaint);

      final Paint linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = spec.color.withValues(alpha: spec.alpha);
      canvas.drawPath(path, linePaint);
    }

    // 3. Radial Melodic Pulse Bars around the inner disc rim (64 subtle glowing frequency ticks)
    // Provides immediate visual confirmation of every single frequency bin jumping with the melody!
    if (isPlaying && bins.isNotEmpty) {
      const int tickCount = 64;
      final double innerTickR = baseDiscRadius + maxRadius * 0.018 + beat * maxRadius * 0.03;
      for (int t = 0; t < tickCount; t++) {
        final double norm = t / tickCount;
        final double angle = norm * math.pi * 2.0 - math.pi / 2;
        final double binVal = _sampleSmoothBin(bins, norm, startBin: 0, endBin: bins.length);
        final double active = math.max(0.0, binVal - 0.03);
        if (active < 0.02) continue;

        final double tickLen = active * maxRadius * 0.19;
        final Offset p1 = Offset(
          center.dx + math.cos(angle) * innerTickR,
          center.dy + math.sin(angle) * innerTickR,
        );
        final Offset p2 = Offset(
          center.dx + math.cos(angle) * (innerTickR + tickLen),
          center.dy + math.sin(angle) * (innerTickR + tickLen),
        );
        final Color tickCol = Color.lerp(c1, c2, (norm * 2.0) % 1.0) ?? c1;
        final Paint tickPaint = Paint()
          ..color = tickCol.withValues(alpha: (0.28 + active * 0.65).clamp(0.15, 0.92))
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p1, p2, tickPaint);
      }
    }

    // 4. Audio-Reactive Luminous Particles pushed outward by each frequency band's peak
    const int particleCount = 20;
    for (int p = 0; p < particleCount; p++) {
      final double norm = p / particleCount;
      final double pAngle = norm * math.pi * 2.0 + phase * 0.12 * (p.isEven ? 1 : -1);
      final int bIdx = (p * 3) % bins.length;
      final double bEnergy = bins[bIdx];
      final double active = math.max(0.0, bEnergy - 0.03);
      final double orbitR = baseDiscRadius +
          maxRadius * (0.12 + 0.18 * ((p % 4) / 3.0)) +
          active * maxRadius * 0.24 +
          beat * maxRadius * 0.06;
      final Offset pos = Offset(
        center.dx + math.cos(pAngle) * orbitR,
        center.dy + math.sin(pAngle) * orbitR,
      );
      final double dotRadius = 1.2 + active * 2.8;
      final Color dotColor = p % 3 == 0 ? c1 : (p % 3 == 1 ? c2 : Colors.white);
      final Paint dotPaint = Paint()
        ..color = dotColor.withValues(alpha: (0.22 + active * 0.75 + treble * 0.2).clamp(0.1, 0.95))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      canvas.drawCircle(pos, dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FluidWaveRipplePainter oldDelegate) {
    return oldDelegate.spectrum != spectrum ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.colors != colors;
  }
}

class _MelodyWaveLayer {
  const _MelodyWaveLayer({
    required this.color,
    required this.baseOffset,
    required this.maxJump,
    required this.startBin,
    required this.endBin,
    required this.harmonicLobes,
    required this.angularDrift,
    required this.strokeWidth,
    required this.glowSigma,
    required this.alpha,
    required this.fillAlpha,
    required this.beatWeight,
  });

  final Color color;
  final double baseOffset;
  final double maxJump;
  final int startBin;
  final int endBin;
  final int harmonicLobes;
  final double angularDrift;
  final double strokeWidth;
  final double glowSigma;
  final double alpha;
  final double fillAlpha;
  final double beatWeight;
}
