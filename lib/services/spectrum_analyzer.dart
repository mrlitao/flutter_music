import 'dart:math' as math;
import 'dart:typed_data';
import '../models/track.dart';
import 'demo_wav_generator.dart';

/// Real-time Radix-2 Cooley-Tukey FFT & Multi-Band Melodic/Rhythmic Spectrum Analyzer.
/// Captures fast transient melody notes, vocal peaks, and drum beats with high dynamic contrast.
class SpectrumAnalyzer {
  static const int fftSize = 256;
  static const int binCount = 32;

  final List<double> _smoothedBins = List<double>.filled(binCount, 0.03);
  final List<double> _prevBins = List<double>.filled(binCount, 0.03);
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
      _phase += 0.005;
      _smoothedBass = _lerp(_smoothedBass, 0.03, 0.16);
      _smoothedMid = _lerp(_smoothedMid, 0.03, 0.16);
      _smoothedTreble = _lerp(_smoothedTreble, 0.02, 0.16);
      _smoothedBeat = _lerp(_smoothedBeat, 0.0, 0.22);
      for (int i = 0; i < binCount; i++) {
        _smoothedBins[i] = _lerp(_smoothedBins[i], 0.03, 0.16);
        _prevBins[i] = _smoothedBins[i];
      }
      return SpectrumFrame(
        bassEnergy: _smoothedBass,
        midEnergy: _smoothedMid,
        trebleEnergy: _smoothedTreble,
        beatPulse: _smoothedBeat,
        bins: List<double>.unmodifiable(_smoothedBins),
        phase: _phase,
      );
    }

    final rawBins = List<double>.filled(binCount, 0.0);
    final pcm = _activePcmBuffer;

    if (webAudioBins != null && webAudioBins.length == binCount) {
      for (int i = 0; i < binCount; i++) {
        rawBins[i] = webAudioBins[i];
      }
    } else if (pcm != null && pcm.length > 44 + fftSize * 4) {
      _computeRealFftBins(pcm, position, rawBins);
    } else {
      _computeHarmonicBins(position, track, rawBins);
    }

    // Apply 5-band Equalizer gains + spectral flux transient enhancement
    // (When a note suddenly appears in bin i, boost its attack so the melody leap is unmistakable!)
    double spectralFlux = 0.0;
    for (int i = 0; i < binCount; i++) {
      final int eqIdx = ((i / binCount) * eqBands.length).floor().clamp(0, eqBands.length - 1);
      final double gainDb = eqBands[eqIdx].gainDb;
      final double eqMultiplier = math.pow(10.0, gainDb / 24.0).toDouble();

      final double rawVal = rawBins[i] * eqMultiplier * scale;
      final double onsetDelta = math.max(0.0, rawVal - _prevBins[i]);
      spectralFlux += onsetDelta;
      _prevBins[i] = rawVal;

      final double target = (rawVal + onsetDelta * 0.85).clamp(0.02, 1.0);
      // Fast attack (0.68) so melody notes jump immediately; snappy decay (0.24) so rests drop cleanly
      final double alpha = target > _smoothedBins[i] ? 0.68 : 0.24;
      _smoothedBins[i] = _lerp(_smoothedBins[i], target, alpha);
    }

    double bassSum = 0.0;
    double bassPeak = 0.0;
    for (int i = 0; i < 6; i++) {
      bassSum += _smoothedBins[i];
      if (_smoothedBins[i] > bassPeak) bassPeak = _smoothedBins[i];
    }
    double midSum = 0.0;
    double midPeak = 0.0;
    for (int i = 6; i < 19; i++) {
      midSum += _smoothedBins[i];
      if (_smoothedBins[i] > midPeak) midPeak = _smoothedBins[i];
    }
    double trebleSum = 0.0;
    double treblePeak = 0.0;
    for (int i = 19; i < binCount; i++) {
      trebleSum += _smoothedBins[i];
      if (_smoothedBins[i] > treblePeak) treblePeak = _smoothedBins[i];
    }

    final double instBass = ((bassSum / 6.0) * 0.55 + bassPeak * 0.45).clamp(0.02, 1.0);
    final double instMid = ((midSum / 13.0) * 0.45 + midPeak * 0.55).clamp(0.02, 1.0);
    final double instTreble = ((trebleSum / 13.0) * 0.45 + treblePeak * 0.55).clamp(0.02, 1.0);

    // Beat & melodic onset detector combining bass transient and full-spectrum note flux
    final double bassDelta = math.max(0.0, instBass - _smoothedBass * 0.86);
    final double normFlux = (spectralFlux / 5.5).clamp(0.0, 1.0);
    final double targetBeat =
        (bassDelta * 3.2 + normFlux * 0.75 + math.pow(instBass, 2.0) * 0.55).clamp(0.0, 1.0);

    _smoothedBass = _lerp(_smoothedBass, instBass, instBass > _smoothedBass ? 0.62 : 0.25);
    _smoothedMid = _lerp(_smoothedMid, instMid, instMid > _smoothedMid ? 0.65 : 0.26);
    _smoothedTreble = _lerp(_smoothedTreble, instTreble, instTreble > _smoothedTreble ? 0.65 : 0.28);
    _smoothedBeat = _lerp(_smoothedBeat, targetBeat, targetBeat > _smoothedBeat ? 0.72 : 0.24);

    // Phase advances gently during quiet passages and surges on rhythmic beats & melodic peaks
    _phase += 0.010 + (_smoothedBeat * 0.055) + (_smoothedMid * 0.032);

    return SpectrumFrame(
      bassEnergy: _smoothedBass,
      midEnergy: _smoothedMid,
      trebleEnergy: _smoothedTreble,
      beatPulse: _smoothedBeat,
      bins: List<double>.unmodifiable(_smoothedBins),
      phase: _phase,
    );
  }

  /// Computes real-time 256-point Radix-2 FFT + waveform RMS envelope from PCM WAV bytes.
  void _computeRealFftBins(Uint8List wavBytes, Duration position, List<double> outBins) {
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
    // Gate out quiet floor and amplify dynamic peaks
    final double rmsEnvelope = math.pow((rms * 2.6).clamp(0.0, 1.0), 1.35).toDouble();

    _inPlaceRadix2Fft(real, imag);

    for (int b = 0; b < binCount; b++) {
      final int startBin = (math.pow(b / binCount, 1.55) * 88).floor().clamp(1, 115);
      final int endBin =
          math.max(startBin + 1, (math.pow((b + 1) / binCount, 1.55) * 88).floor().clamp(2, 124));
      double peakMag = 0.0;
      for (int k = startBin; k < endBin; k++) {
        final mag = math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
        if (mag > peakMag) peakMag = mag;
      }
      // Frequency-dependent perceptual weight + sharp contrast curve
      final double weight = 0.14 + (b / binCount) * 0.42;
      final double norm = (peakMag * weight).clamp(0.0, 1.0);
      final double contrasted = math.pow(norm, 1.45).toDouble() * (0.35 + rmsEnvelope * 0.95);
      outBins[b] = contrasted.clamp(0.02, 1.0);
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

  /// Dynamic rhythmic & melodic note envelope synthesizer for native compressed streams
  /// when raw PCM buffer is decoded by OS hardware.
  void _computeHarmonicBins(Duration position, Track track, List<double> outBins) {
    final double t = position.inMilliseconds / 1000.0;
    final int seed = track.title.hashCode.abs();
    final double bpm = 114.0 + (seed % 28);
    final double beatSec = 60.0 / bpm;
    final double sixteenthSec = beatSec / 4.0;

    final int step16 = ((t / sixteenthSec).floor()) % 16;
    final double stepPhase = (t % sixteenthSec) / sixteenthSec;
    final double beatPhase = (t % beatSec) / beatSec;

    // Kick & Snare rhythmic envelopes
    final double kickHit = (step16 % 4 == 0 || step16 == 11) ? math.exp(-beatPhase * 9.5) : 0.05;
    final double snareHit = (step16 % 8 == 4) ? math.exp(-beatPhase * 13.0) : 0.04;

    // Melodic note contour (active on rhythmic steps, resting on off-steps)
    const List<int> gate = [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0];
    final bool hasNote = gate[step16] == 1;
    final int activeMelodyBin = 7 + ((step16 * 3 + seed) % 14);
    final double noteEnv = hasNote ? math.exp(-stepPhase * 3.4) : 0.06;

    for (int i = 0; i < binCount; i++) {
      double val = 0.03;
      if (i < 6) {
        // Sub-bass & kick drums
        val = kickHit * (0.95 - i * 0.08);
      } else if (i < 21) {
        // Melody & vocal bands: peak sharply around the currently playing note pitch!
        final double dist = (i - activeMelodyBin).abs().toDouble();
        final double pitchBell = math.exp(-(dist * dist) / 4.5);
        val = noteEnv * pitchBell * 0.92 + snareHit * 0.35;
      } else {
        // High-frequency hi-hats & harmonic shimmer
        final double hihat = (step16.isEven ? math.exp(-stepPhase * 12.0) : 0.12);
        val = hihat * 0.55 + noteEnv * 0.28;
      }
      outBins[i] = val.clamp(0.02, 0.98);
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
