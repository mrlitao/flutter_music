import 'dart:math' as math;
import 'dart:typed_data';
import '../models/track.dart';
import 'demo_wav_generator.dart';

/// Real-time 512-point Radix-2 Cooley-Tukey FFT & 12-Tone Chromatic Pitch Analyzer.
/// Maps audio frequencies onto the 12 fixed musical pitch classes (C, C#, D, D#, E, F, F#, G, G#, A, A#, B)
/// and maintains delayed radial ripple trails so active melody notes & chords diffuse outward smoothly.
class SpectrumAnalyzer {
  static const int fftSize = 512;
  static const int binCount = 32;
  static const int pitchCount = 12;

  final List<double> _smoothedBins = List<double>.filled(binCount, 0.03);
  final List<double> _prevBins = List<double>.filled(binCount, 0.03);

  final List<double> _smoothedPitch = List<double>.filled(pitchCount, 0.02);
  final List<double> _pitchTrail1 = List<double>.filled(pitchCount, 0.02);
  final List<double> _pitchTrail2 = List<double>.filled(pitchCount, 0.02);

  double _smoothedBass = 0.04;
  double _smoothedMid = 0.04;
  double _smoothedTreble = 0.03;
  double _smoothedBeat = 0.0;
  double _phase = 0.0;

  Uint8List? _activePcmBuffer;
  int _activeSampleRate = 22050;
  int _activeBytesPerSample = 2;
  int _activeChannels = 1;
  String? _loadedTrackId;

  Future<void> prepareForTrack(Track track, {Uint8List? rawWavBytes}) async {
    if (_loadedTrackId == track.id && _activePcmBuffer != null) return;
    _loadedTrackId = track.id;
    _activePcmBuffer = null;

    if (track.isBuiltInDemo) {
      _activePcmBuffer = DemoWavGenerator.getOrGenerateWavBytes(track.demoPresetIndex);
      _activeSampleRate = 22050;
      _activeBytesPerSample = 2;
      _activeChannels = 1;
      return;
    }

    if (rawWavBytes != null && rawWavBytes.length > 44) {
      try {
        final bd = ByteData.sublistView(rawWavBytes);
        _activeChannels = bd.getUint16(22, Endian.little).clamp(1, 2);
        _activeSampleRate = bd.getUint32(24, Endian.little).clamp(8000, 192000);
        final bits = bd.getUint16(34, Endian.little);
        _activeBytesPerSample = (bits ~/ 8).clamp(1, 4);
        _activePcmBuffer = rawWavBytes;
      } catch (_) {
        _activePcmBuffer = null;
      }
    }
  }

  SpectrumFrame computeFrame({
    required bool isPlaying,
    required Duration position,
    required Track track,
    required List<EqualizerBand> eqBands,
    required double intensity,
    List<double>? webAudioBins,
  }) {
    final double scale = intensity.clamp(0.15, 1.5);

    if (!isPlaying) {
      _smoothedBass = _lerp(_smoothedBass, 0.03, 0.14);
      _smoothedMid = _lerp(_smoothedMid, 0.03, 0.14);
      _smoothedTreble = _lerp(_smoothedTreble, 0.02, 0.14);
      _smoothedBeat = _lerp(_smoothedBeat, 0.0, 0.18);
      for (int i = 0; i < binCount; i++) {
        _smoothedBins[i] = _lerp(_smoothedBins[i], 0.03, 0.14);
        _prevBins[i] = _smoothedBins[i];
      }
      for (int p = 0; p < pitchCount; p++) {
        _smoothedPitch[p] = _lerp(_smoothedPitch[p], 0.02, 0.16);
        _pitchTrail1[p] = _lerp(_pitchTrail1[p], _smoothedPitch[p], 0.18);
        _pitchTrail2[p] = _lerp(_pitchTrail2[p], _pitchTrail1[p], 0.14);
      }
      return SpectrumFrame(
        bassEnergy: _smoothedBass,
        midEnergy: _smoothedMid,
        trebleEnergy: _smoothedTreble,
        beatPulse: _smoothedBeat,
        bins: List<double>.unmodifiable(_smoothedBins),
        phase: _phase,
        pitchClasses: List<double>.unmodifiable(_smoothedPitch),
        pitchTrail1: List<double>.unmodifiable(_pitchTrail1),
        pitchTrail2: List<double>.unmodifiable(_pitchTrail2),
      );
    }

    final rawBins = List<double>.filled(binCount, 0.0);
    final rawPitch = List<double>.filled(pitchCount, 0.0);
    final pcm = _activePcmBuffer;

    if (webAudioBins != null && webAudioBins.length == binCount) {
      for (int i = 0; i < binCount; i++) {
        rawBins[i] = webAudioBins[i];
      }
      _derivePitchClassesFromBins(rawBins, rawPitch);
    } else if (pcm != null && pcm.length > 44 + fftSize * 4) {
      _computeRealFftAndChroma(pcm, position, rawBins, rawPitch);
    } else {
      _computeMusicalChordAndMelody(position, track, rawBins, rawPitch);
    }

    // Smooth 32-band EQ-modulated bins
    double spectralFlux = 0.0;
    for (int i = 0; i < binCount; i++) {
      final int eqIdx = ((i / binCount) * eqBands.length).floor().clamp(0, eqBands.length - 1);
      final double gainDb = eqBands[eqIdx].gainDb;
      final double eqMultiplier = math.pow(10.0, gainDb / 24.0).toDouble();

      final double rawVal = rawBins[i] * eqMultiplier * scale;
      final double onsetDelta = math.max(0.0, rawVal - _prevBins[i]);
      spectralFlux += onsetDelta;
      _prevBins[i] = rawVal;

      final double target = (rawVal + onsetDelta * 0.65).clamp(0.02, 1.0);
      final double alpha = target > _smoothedBins[i] ? 0.58 : 0.22;
      _smoothedBins[i] = _lerp(_smoothedBins[i], target, alpha);
    }

    // Smooth 12 fixed pitch classes & propagate radial outward ripple trails
    for (int p = 0; p < pitchCount; p++) {
      final double targetP = (rawPitch[p] * scale).clamp(0.02, 1.0);
      final double alphaP = targetP > _smoothedPitch[p] ? 0.55 : 0.16;
      _smoothedPitch[p] = _lerp(_smoothedPitch[p], targetP, alphaP);
      // Outer rings follow inner ring with smooth radial propagation lag (ripple diffusion)
      _pitchTrail1[p] = _lerp(_pitchTrail1[p], _smoothedPitch[p], 0.24);
      _pitchTrail2[p] = _lerp(_pitchTrail2[p], _pitchTrail1[p], 0.16);
    }

    double bassSum = 0.0;
    for (int i = 0; i < 6; i++) {
      bassSum += _smoothedBins[i];
    }
    double midSum = 0.0;
    for (int i = 6; i < 19; i++) {
      midSum += _smoothedBins[i];
    }
    double trebleSum = 0.0;
    for (int i = 19; i < binCount; i++) {
      trebleSum += _smoothedBins[i];
    }

    final double instBass = (bassSum / 6.0).clamp(0.02, 1.0);
    final double instMid = (midSum / 13.0).clamp(0.02, 1.0);
    final double instTreble = (trebleSum / 13.0).clamp(0.02, 1.0);
    final double bassDelta = math.max(0.0, instBass - _smoothedBass * 0.86);
    final double normFlux = (spectralFlux / 6.0).clamp(0.0, 1.0);
    final double targetBeat = (bassDelta * 2.5 + normFlux * 0.6).clamp(0.0, 1.0);

    _smoothedBass = _lerp(_smoothedBass, instBass, 0.45);
    _smoothedMid = _lerp(_smoothedMid, instMid, 0.45);
    _smoothedTreble = _lerp(_smoothedTreble, instTreble, 0.45);
    _smoothedBeat = _lerp(_smoothedBeat, targetBeat, 0.45);
    _phase += 0.02 + (_smoothedMid * 0.025);

    return SpectrumFrame(
      bassEnergy: _smoothedBass,
      midEnergy: _smoothedMid,
      trebleEnergy: _smoothedTreble,
      beatPulse: _smoothedBeat,
      bins: List<double>.unmodifiable(_smoothedBins),
      phase: _phase,
      pitchClasses: List<double>.unmodifiable(_smoothedPitch),
      pitchTrail1: List<double>.unmodifiable(_pitchTrail1),
      pitchTrail2: List<double>.unmodifiable(_pitchTrail2),
    );
  }

  /// Computes 512-point FFT and maps each frequency bin `f = k * sampleRate / N`
  /// directly to its exact 12-tone pitch class (`C=0 .. B=11`).
  void _computeRealFftAndChroma(
    Uint8List wavBytes,
    Duration position,
    List<double> outBins,
    List<double> outPitch,
  ) {
    final int frameBytes = _activeBytesPerSample * _activeChannels;
    final int payloadBytes = wavBytes.length - 44;
    if (payloadBytes <= fftSize * frameBytes) return;

    final int sampleIndex = ((position.inMilliseconds / 1000.0) * _activeSampleRate).round();
    final int byteOffset = 44 + ((sampleIndex * frameBytes) % (payloadBytes - fftSize * frameBytes));

    final real = Float64List(fftSize);
    final imag = Float64List(fftSize);
    final bd = ByteData.sublistView(wavBytes);
    double rmsSum = 0.0;

    for (int i = 0; i < fftSize; i++) {
      final int pos = byteOffset + i * frameBytes;
      double sample = 0.0;
      if (pos + 2 <= wavBytes.length) {
        if (_activeBytesPerSample == 1) {
          sample = (wavBytes[pos] - 128) / 128.0;
        } else {
          sample = bd.getInt16(pos, Endian.little) / 32768.0;
        }
      }
      rmsSum += sample * sample;
      final double hann = 0.5 * (1.0 - math.cos((2.0 * math.pi * i) / (fftSize - 1)));
      real[i] = sample * hann;
      imag[i] = 0.0;
    }

    final double rms = math.sqrt(rmsSum / fftSize).clamp(0.0, 1.0);
    final double rmsEnvelope = math.pow((rms * 2.5).clamp(0.0, 1.0), 1.2).toDouble();

    _inPlaceRadix2Fft(real, imag);

    final int halfN = fftSize ~/ 2;
    // 1. Fill 32 logarithmic display bins
    for (int b = 0; b < binCount; b++) {
      final int startBin = (math.pow(b / binCount, 1.6) * (halfN * 0.8)).floor().clamp(1, halfN - 2);
      final int endBin = math.max(
        startBin + 1,
        (math.pow((b + 1) / binCount, 1.6) * (halfN * 0.8)).floor().clamp(2, halfN - 1),
      );
      double peakMag = 0.0;
      for (int k = startBin; k < endBin; k++) {
        final mag = math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
        if (mag > peakMag) peakMag = mag;
      }
      final double weight = 0.08 + (b / binCount) * 0.25;
      final double norm = (peakMag * weight).clamp(0.0, 1.0);
      outBins[b] = (math.pow(norm, 1.35).toDouble() * (0.3 + rmsEnvelope * 0.9)).clamp(0.02, 1.0);
    }

    // 2. Accumulate musical frequencies (65Hz .. 2400Hz) into exact 12 chromatic pitch classes
    final double binHz = _activeSampleRate / fftSize;
    double maxChroma = 0.001;
    for (int k = 1; k < halfN; k++) {
      final double freq = k * binHz;
      if (freq < 65.0 || freq > 2400.0) continue;
      final double mag = math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
      final double midiFloat = 69.0 + 12.0 * (math.log(freq / 440.0) / math.ln2);
      final int pitchClass = (midiFloat.round() % 12 + 12) % 12;
      outPitch[pitchClass] += mag * mag;
      if (outPitch[pitchClass] > maxChroma) {
        maxChroma = outPitch[pitchClass];
      }
    }

    for (int p = 0; p < pitchCount; p++) {
      // Relative dominance within the active chord/melody + overall loudness gate
      final double rel = (outPitch[p] / maxChroma).clamp(0.0, 1.0);
      outPitch[p] = (math.pow(rel, 0.75).toDouble() * (0.2 + rmsEnvelope * 0.95)).clamp(0.02, 1.0);
    }
  }

  /// Derives 12 chromatic pitch classes from Web Audio 32-band logarithmic bins.
  void _derivePitchClassesFromBins(List<double> bins, List<double> outPitch) {
    // 32 logarithmic bins span ~45Hz to ~10kHz (~96 semitones / ~3 semitones per bin)
    double maxVal = 0.001;
    for (int i = 0; i < bins.length; i++) {
      final double approxFreq = 45.0 * math.pow(2.0, (i / bins.length) * 7.8);
      final double midiFloat = 69.0 + 12.0 * (math.log(approxFreq / 440.0) / math.ln2);
      final int pc = (midiFloat.round() % 12 + 12) % 12;
      final int pcNext = (pc + 1) % 12;
      outPitch[pc] += bins[i];
      outPitch[pcNext] += bins[i] * 0.35;
      if (outPitch[pc] > maxVal) maxVal = outPitch[pc];
    }
    for (int p = 0; p < pitchCount; p++) {
      outPitch[p] = math.pow((outPitch[p] / maxVal).clamp(0.0, 1.0), 1.3).toDouble().clamp(0.02, 1.0);
    }
  }

  /// Generates realistic musical chord progressions & melody notes into the 12 fixed pitch classes
  /// when playing native compressed formats (MP3/MP4/FLAC) without raw PCM access.
  void _computeMusicalChordAndMelody(
    Duration position,
    Track track,
    List<double> outBins,
    List<double> outPitch,
  ) {
    final double t = position.inMilliseconds / 1000.0;
    final int seed = track.title.hashCode.abs();
    final double bpm = 112.0 + (seed % 24);
    final double beatSec = 60.0 / bpm;
    final double eighthSec = beatSec / 2.0;

    // 4-bar chord progression in pitch classes (0=C, 2=D, 4=E, 5=F, 7=G, 9=A, 11=B)
    final int keyOffset = seed % 12;
    const progressions = <List<List<int>>>[
      // Am7 -> Fmaj7 -> Cmaj7 -> G6
      [
        [9, 0, 4, 7],
        [5, 9, 0, 4],
        [0, 4, 7, 11],
        [7, 11, 2, 4],
      ],
      // Dm7 -> G7 -> Cmaj9 -> Am7
      [
        [2, 5, 9, 0],
        [7, 11, 2, 5],
        [0, 4, 7, 2],
        [9, 0, 4, 7],
      ],
    ];
    final prog = progressions[seed % progressions.length];
    final int barIdx = ((t / (beatSec * 4.0)).floor()) % prog.length;
    final List<int> chordNotes = prog[barIdx];

    final double barPhase = (t % (beatSec * 4.0)) / (beatSec * 4.0);
    final double chordSwell = 0.45 + 0.40 * math.sin(barPhase * math.pi);

    // Activate all notes of the current chord at their fixed angles
    for (int i = 0; i < chordNotes.length; i++) {
      final int pc = (chordNotes[i] + keyOffset) % 12;
      outPitch[pc] = (chordSwell * (i == 0 ? 1.0 : 0.78)).clamp(0.05, 0.95);
    }

    // Highlight the active lead melody note jumping along the chord/scale
    final int eighthStep = (t / eighthSec).floor();
    final double stepPhase = (t % eighthSec) / eighthSec;
    final int melodyNote = (chordNotes[(eighthStep * 3) % chordNotes.length] + keyOffset) % 12;
    final double noteEnv = math.exp(-stepPhase * 2.8);
    outPitch[melodyNote] = math.max(outPitch[melodyNote], 0.35 + noteEnv * 0.65).clamp(0.05, 1.0);

    // Fill 32-band spectrum coherently
    for (int i = 0; i < binCount; i++) {
      final int pc = (i * 3) % 12;
      outBins[i] = (outPitch[pc] * 0.85 + noteEnv * 0.15).clamp(0.03, 0.95);
    }
  }

  static void _inPlaceRadix2Fft(Float64List real, Float64List imag) {
    final int n = real.length;
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
      if (i < j) {
        final tr = real[i];
        final ti = imag[i];
        real[i] = real[j];
        imag[i] = imag[j];
        real[j] = tr;
        imag[j] = ti;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }

    for (int len = 2; len <= n; len <<= 1) {
      final double angle = -2.0 * math.pi / len;
      final double wlenR = math.cos(angle);
      final double wlenI = math.sin(angle);
      final int half = len >> 1;
      for (int i = 0; i < n; i += len) {
        double wR = 1.0;
        double wI = 0.0;
        for (int k = 0; k < half; k++) {
          final int u = i + k;
          final int v = u + half;
          final double tR = wR * real[v] - wI * imag[v];
          final double tI = wR * imag[v] + wI * real[v];
          real[v] = real[u] - tR;
          imag[v] = imag[u] - tI;
          real[u] += tR;
          imag[u] += tI;
          final double nextWR = wR * wlenR - wI * wlenI;
          wI = wR * wlenI + wI * wlenR;
          wR = nextWR;
        }
      }
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
