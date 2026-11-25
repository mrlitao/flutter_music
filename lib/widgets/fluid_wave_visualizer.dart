import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../models/track.dart';
import 'glass_widgets.dart';

/// Audio-Reactive Fixed-Pitch Polar Streamline Ripple Visualizer.
/// - Zero distracting disc scaling/bouncing animations on the central vinyl/album cover.
/// - Fixed 360° angular positions represent the 12 chromatic musical scales & notes
///   (`C, C#, D, D#, E, F, F#, G, G#, A, A#, B`).
/// - When melodies or chords play, the streamline ripples expand & diffuse radially outward
///   at the exact fixed angles of the active notes!
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
              // 1. Fixed-Angle Musical Pitch-Class Streamline Ripple Canvas
              CustomPaint(
                size: Size(size, size),
                painter: FluidWaveRipplePainter(
                  spectrum: spectrum,
                  colors: colors,
                  isPlaying: isPlaying,
                ),
              ),

              // 2. Steady Central Album / Vinyl Disc (No scaling animation!)
              Container(
                width: discBaseSize,
                height: discBaseSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (colors.isNotEmpty ? colors[0] : const Color(0xFF06B6D4))
                          .withValues(alpha: 0.30 + spectrum.midEnergy * 0.25),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.42),
                    width: 2.0,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// CustomPainter mapping the 12 chromatic pitch classes (`C .. B`) to fixed 30° sectors
/// around the circle (`-π/2` top clockwise) and diffusing concentric streamline ripples
/// radially outward whenever matching melody notes or chords are played.
class FluidWaveRipplePainter extends CustomPainter {
  const FluidWaveRipplePainter({
    required this.spectrum,
    required this.colors,
    required this.isPlaying,
  });

  final SpectrumFrame spectrum;
  final List<Color> colors;
  final bool isPlaying;

  static const List<String> _noteNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  /// Smooth cyclic Catmull-Rom / cosine interpolation across the 12 fixed pitch classes.
  /// Position `0.0` aligns with `-π/2` (12 o'clock = Note C), `1/12` = C#, ..., `11/12` = B.
  double _samplePitchAtNormalizedAngle(List<double> pitchValues, double normAngle) {
    if (pitchValues.length < 12) return 0.02;
    final double wrapped = normAngle - normAngle.floorToDouble();
    final double exactIdx = wrapped * 12.0;
    final int i0 = exactIdx.floor() % 12;
    final int i1 = (i0 + 1) % 12;
    final double frac = exactIdx - exactIdx.floorToDouble();
    final double mu = (1.0 - math.cos(frac * math.pi)) * 0.5;
    return pitchValues[i0] + (pitchValues[i1] - pitchValues[i0]) * mu;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxRadius = math.min(size.width, size.height) / 2;
    final double baseDiscRadius = maxRadius * 0.42;

    final Color c1 = colors.isNotEmpty ? colors[0] : const Color(0xFF06B6D4);
    final Color c2 = colors.length > 1 ? colors[1] : const Color(0xFFD946EF);
    final Color c3 = colors.length > 2 ? colors[2] : const Color(0xFF6366F1);

    final List<double> innerPitch = spectrum.pitchClasses;
    final List<double> midPitch = spectrum.pitchTrail1;
    final List<double> outerPitch = spectrum.pitchTrail2;

    // 1. Subtle Ambient Radial Glow
    final Rect auraRect = Rect.fromCircle(center: center, radius: maxRadius * 0.96);
    final Paint auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          c1.withValues(alpha: (0.14 + spectrum.midEnergy * 0.20).clamp(0.08, 0.45)),
          c2.withValues(alpha: (0.08 + spectrum.bassEnergy * 0.14).clamp(0.04, 0.30)),
          Colors.transparent,
        ],
        stops: const [0.36, 0.72, 1.0],
      ).createShader(auraRect);
    canvas.drawCircle(center, maxRadius * 0.96, auraPaint);

    // 2. Fixed-Angle Musical Note Radial Guidelines & Luminous Scale Markers (C .. B)
    final double guideInnerR = baseDiscRadius + maxRadius * 0.02;
    final double guideOuterR = maxRadius * 0.90;
    for (int n = 0; n < 12; n++) {
      final double theta = -math.pi / 2 + (n / 12.0) * math.pi * 2.0;
      final double noteEnergy =
          isPlaying && n < innerPitch.length ? math.max(0.0, innerPitch[n] - 0.04) : 0.0;

      final Color noteColor = Color.lerp(c1, c2, n / 11.0) ?? c1;
      final Paint rayPaint = Paint()
        ..color = noteColor.withValues(alpha: (0.08 + noteEnergy * 0.38).clamp(0.06, 0.55))
        ..strokeWidth = 1.0 + noteEnergy * 1.4;
      canvas.drawLine(
        Offset(center.dx + math.cos(theta) * guideInnerR, center.dy + math.sin(theta) * guideInnerR),
        Offset(center.dx + math.cos(theta) * guideOuterR, center.dy + math.sin(theta) * guideOuterR),
        rayPaint,
      );

      // Fixed outer note label (C, C#, D, ... B) that glows brightly when that note/chord sounds
      final double labelR = maxRadius * 0.945;
      final Offset labelCenter = Offset(
        center.dx + math.cos(theta) * labelR,
        center.dy + math.sin(theta) * labelR,
      );
      if (noteEnergy > 0.12) {
        final Paint noteGlow = Paint()
          ..color = noteColor.withValues(alpha: (noteEnergy * 0.65).clamp(0.1, 0.75))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
        canvas.drawCircle(labelCenter, 6.0 + noteEnergy * 4.0, noteGlow);
      }
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: _noteNames[n],
          style: TextStyle(
            fontSize: noteEnergy > 0.25 ? 10.5 : 9.0,
            fontWeight: noteEnergy > 0.25 ? FontWeight.w800 : FontWeight.w500,
            color: Colors.white.withValues(alpha: (0.32 + noteEnergy * 0.68).clamp(0.28, 1.0)),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(labelCenter.dx - tp.width / 2, labelCenter.dy - tp.height / 2));
    }

    // 3. Five Fixed-Angle Concentric Streamline Ripple Layers (Zero rotation, pure radial diffusion!)
    // Inner layers react immediately to `innerPitch`; outer layers diffuse outward via `midPitch` & `outerPitch`.
    final layers = <_PitchRippleLayer>[
      _PitchRippleLayer(
        color: c1,
        baseOffset: maxRadius * 0.035,
        maxSpread: maxRadius * 0.22,
        pitchData: innerPitch,
        strokeWidth: 2.6,
        glowSigma: 8.5,
        alpha: 0.92,
        fillAlpha: 0.09,
      ),
      _PitchRippleLayer(
        color: c2,
        baseOffset: maxRadius * 0.095,
        maxSpread: maxRadius * 0.25,
        pitchData: innerPitch,
        strokeWidth: 2.2,
        glowSigma: 7.5,
        alpha: 0.80,
        fillAlpha: 0.06,
      ),
      _PitchRippleLayer(
        color: c3,
        baseOffset: maxRadius * 0.16,
        maxSpread: maxRadius * 0.26,
        pitchData: midPitch,
        strokeWidth: 1.9,
        glowSigma: 6.5,
        alpha: 0.68,
        fillAlpha: 0.04,
      ),
      _PitchRippleLayer(
        color: Color.lerp(c1, c2, 0.5) ?? c1,
        baseOffset: maxRadius * 0.225,
        maxSpread: maxRadius * 0.25,
        pitchData: outerPitch,
        strokeWidth: 1.5,
        glowSigma: 5.5,
        alpha: 0.54,
        fillAlpha: 0.025,
      ),
      _PitchRippleLayer(
        color: Color.lerp(c2, Colors.white, 0.35) ?? c2,
        baseOffset: maxRadius * 0.285,
        maxSpread: maxRadius * 0.22,
        pitchData: outerPitch,
        strokeWidth: 1.2,
        glowSigma: 4.5,
        alpha: 0.40,
        fillAlpha: 0.0,
      ),
    ];

    const int segments = 180;

    for (int l = 0; l < layers.length; l++) {
      final spec = layers[l];
      final Path path = Path();

      for (int i = 0; i <= segments; i++) {
        final double norm = i / segments;
        // Fixed angle starting at 12 o'clock (-π/2) clockwise: norm=0 is C, norm=1/12 is C#, etc.
        final double theta = -math.pi / 2 + norm * math.pi * 2.0;

        final double pitchEnergy = _samplePitchAtNormalizedAngle(spec.pitchData, norm);
        final double activeSignal = isPlaying ? math.max(0.0, pitchEnergy - 0.03) : 0.0;

        // Smooth radial expansion strictly along the active musical note/chord angles
        final double noteDiffusion = activeSignal * spec.maxSpread;

        final double r = baseDiscRadius + spec.baseOffset + noteDiffusion;
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

    // 4. Diffusing Luminous Note Nodes along the 12 fixed pitch angles
    if (isPlaying) {
      for (int n = 0; n < 12; n++) {
        final double energy = math.max(0.0, innerPitch[n] - 0.04);
        if (energy < 0.08) continue;
        final double theta = -math.pi / 2 + (n / 12.0) * math.pi * 2.0;
        final double nodeR = baseDiscRadius + maxRadius * 0.06 + energy * maxRadius * 0.36;
        final Offset pos = Offset(
          center.dx + math.cos(theta) * nodeR,
          center.dy + math.sin(theta) * nodeR,
        );
        final Color dotColor = Color.lerp(c1, c2, n / 11.0) ?? c1;
        final Paint dotPaint = Paint()
          ..color = dotColor.withValues(alpha: (0.4 + energy * 0.6).clamp(0.2, 0.98))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
        canvas.drawCircle(pos, 2.2 + energy * 3.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FluidWaveRipplePainter oldDelegate) {
    return oldDelegate.spectrum != spectrum ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.colors != colors;
  }
}

class _PitchRippleLayer {
  const _PitchRippleLayer({
    required this.color,
    required this.baseOffset,
    required this.maxSpread,
    required this.pitchData,
    required this.strokeWidth,
    required this.glowSigma,
    required this.alpha,
    required this.fillAlpha,
  });

  final Color color;
  final double baseOffset;
  final double maxSpread;
  final List<double> pitchData;
  final double strokeWidth;
  final double glowSigma;
  final double alpha;
  final double fillAlpha;
}
