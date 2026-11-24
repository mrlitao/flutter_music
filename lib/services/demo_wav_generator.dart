import 'dart:math' as math;
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../models/track.dart';

/// Synthesizes real playable 22.05kHz 16-bit PCM `.wav` tracks in memory
/// so the user can immediately experience real audio playback and real PCM-driven
/// fluid wave ripple visualization across Web (Chrome/Edge), Windows, iOS, Android, and HarmonyOS.
class DemoWavGenerator {
  static final Map<int, Uint8List> _cachedWavBytes = {};

  static List<Track> buildShowcaseTracks() {
    return [
      const Track(
        id: 'demo_neon_horizon',
        title: 'Neon Horizon (极光流线)',
        artist: 'Aether & Glass Ensemble',
        album: 'Holographic Reflections',
        filePath: 'builtin://demo_0.wav',
        duration: Duration(seconds: 24),
        formatBadge: 'WAV 16bit/44.1kHz',
        folderPath: '内置高保真声学演示曲库',
        bitrateKbps: 1411,
        sampleRateHz: 44100,
        bitDepth: 16,
        isFavorite: true,
        isBuiltInDemo: true,
        demoPresetIndex: 0,
        importedTimestampMs: 1700000001000,
        playCount: 18,
        paletteColors: [
          Color(0xFF06B6D4),
          Color(0xFFD946EF),
          Color(0xFF6366F1),
        ],
        lyrics: [
          LyricLine(
            timestamp: Duration(seconds: 0),
            text: '穿过城市夜色与全息毛玻璃微光',
            translation: 'Through city nightscapes and holographic frosted light',
          ),
          LyricLine(
            timestamp: Duration(seconds: 4),
            text: '流线波纹在耳畔随低频节拍绽放 ♪',
            translation: 'Streamline ripples bloom beside your ears with every bass beat',
          ),
          LyricLine(
            timestamp: Duration(seconds: 8),
            text: '极坐标谐波环绕着黑胶唱盘轻轻旋转',
            translation: 'Polar harmonic rings orbit the spinning vinyl disc',
          ),
          LyricLine(
            timestamp: Duration(seconds: 12),
            text: '每一次呼吸都化作深邃的星海律动',
            translation: 'Every breath transforms into a deep starry pulse',
          ),
          LyricLine(
            timestamp: Duration(seconds: 16),
            text: '跨端无损声学引擎 · 实时 FFT 频谱共鸣',
            translation: 'Cross-platform lossless engine · Real-time FFT resonance',
          ),
          LyricLine(
            timestamp: Duration(seconds: 20),
            text: '在纯粹通透的磨砂声场里找回感动',
            translation: 'Rediscover emotion inside a pure translucent soundstage',
          ),
        ],
      ),
      const Track(
        id: 'demo_crystal_rain',
        title: 'Crystal Raindrops (琉璃雨滴)',
        artist: 'Luna Synth',
        album: 'Velvet Mist Sessions',
        filePath: 'builtin://demo_1.wav',
        duration: Duration(seconds: 24),
        formatBadge: 'WAV 16bit/44.1kHz',
        folderPath: '内置高保真声学演示曲库',
        bitrateKbps: 1411,
        sampleRateHz: 44100,
        bitDepth: 16,
        isFavorite: false,
        isBuiltInDemo: true,
        demoPresetIndex: 1,
        importedTimestampMs: 1700000002000,
        playCount: 7,
        paletteColors: [
          Color(0xFFF59E0B),
          Color(0xFFF43F5E),
          Color(0xFFEC4899),
        ],
        lyrics: [
          LyricLine(
            timestamp: Duration(seconds: 0),
            text: '细雨落在半透明的磨砂玻璃窗沿',
            translation: 'Gentle rain falls upon the translucent frosted sill',
          ),
          LyricLine(
            timestamp: Duration(seconds: 5),
            text: '温暖的落日流金浸染每一道水波纹 ♪',
            translation: 'Warm sunset gold tints every rippling wave',
          ),
          LyricLine(
            timestamp: Duration(seconds: 10),
            text: '清脆琶音如雨滴坠入静谧湖心',
            translation: 'Crisp arpeggios drop like rain into a tranquil lake',
          ),
          LyricLine(
            timestamp: Duration(seconds: 15),
            text: '层层涟漪随和弦起伏向外舒展',
            translation: 'Layered ripples expand outward with the rising chords',
          ),
          LyricLine(
            timestamp: Duration(seconds: 20),
            text: '余音在暮色与星光之间缓缓回荡',
            translation: 'Echoes linger softly between twilight and starlight',
          ),
        ],
      ),
      const Track(
        id: 'demo_emerald_pulse',
        title: 'Deep Sea Emerald (深海翡翠)',
        artist: 'Oceanic Harmonics',
        album: 'Bioluminescent Waves',
        filePath: 'builtin://demo_2.wav',
        duration: Duration(seconds: 24),
        formatBadge: 'WAV 16bit/44.1kHz',
        folderPath: '内置高保真声学演示曲库',
        bitrateKbps: 1411,
        sampleRateHz: 44100,
        bitDepth: 16,
        isFavorite: true,
        isBuiltInDemo: true,
        demoPresetIndex: 2,
        importedTimestampMs: 1700000003000,
        playCount: 25,
        paletteColors: [
          Color(0xFF10B981),
          Color(0xFF06B6D4),
          Color(0xFF3B82F6),
        ],
        lyrics: [
          LyricLine(
            timestamp: Duration(seconds: 0),
            text: '潜入微光闪烁的深海翡翠梦境',
            translation: 'Diving into a bioluminescent emerald ocean dream',
          ),
          LyricLine(
            timestamp: Duration(seconds: 5),
            text: '深沉低频如同洋流涌动般绵延不绝 ♪',
            translation: 'Deep sub-bass flows endlessly like ocean currents',
          ),
          LyricLine(
            timestamp: Duration(seconds: 11),
            text: '流线波峰与波谷交织出灵动几何',
            translation: 'Fluid crests and troughs weave living geometry',
          ),
          LyricLine(
            timestamp: Duration(seconds: 17),
            text: '让心灵随每一次声波律动自由漂浮',
            translation: 'Let your spirit drift freely with every acoustic wave',
          ),
        ],
      ),
      const Track(
        id: 'demo_cyber_bloom',
        title: 'Cybernetic Bloom (赛博花开)',
        artist: 'Nova Pulse',
        album: 'Future Glass 2077',
        filePath: 'builtin://demo_3.wav',
        duration: Duration(seconds: 24),
        formatBadge: 'WAV 16bit/44.1kHz',
        folderPath: '内置高保真声学演示曲库',
        bitrateKbps: 1411,
        sampleRateHz: 44100,
        bitDepth: 16,
        isFavorite: false,
        isBuiltInDemo: true,
        demoPresetIndex: 3,
        importedTimestampMs: 1700000004000,
        playCount: 12,
        paletteColors: [
          Color(0xFFFF2E93),
          Color(0xFF7928CA),
          Color(0xFF00DF89),
        ],
        lyrics: [
          LyricLine(
            timestamp: Duration(seconds: 0),
            text: '高频泛音划破寂静的数字天际',
            translation: 'High overtones slice across the silent digital sky',
          ),
          LyricLine(
            timestamp: Duration(seconds: 5),
            text: '多层流线光环随电子鼓点热烈跳动 ♪',
            translation: 'Multi-layered streamline halos dance to electronic drums',
          ),
          LyricLine(
            timestamp: Duration(seconds: 11),
            text: 'Windows · Web · iOS · Android · 鸿蒙同频共鸣',
            translation: 'Resonating in harmony across Windows, Web, iOS, Android & HarmonyOS',
          ),
          LyricLine(
            timestamp: Duration(seconds: 17),
            text: '每一帧色彩都为你绽放绚烂流光',
            translation: 'Every frame blooms with radiant aurora light for you',
          ),
        ],
      ),
    ];
  }

  /// Generates a 24-second 22.05kHz mono 16-bit PCM WAV byte buffer with musical chords,
  /// sub-bass pulse, and melodic arpeggios for real playback and real FFT analysis.
  static Uint8List getOrGenerateWavBytes(int presetIndex) {
    final existing = _cachedWavBytes[presetIndex];
    if (existing != null) return existing;

    const int sampleRate = 22050;
    const int durationSeconds = 24;
    const int numSamples = sampleRate * durationSeconds;
    const int dataSize = numSamples * 2; // 16-bit mono
    final buffer = Uint8List(44 + dataSize);
    final bd = ByteData.sublistView(buffer);

    // RIFF header
    buffer.setRange(0, 4, 'RIFF'.codeUnits);
    bd.setUint32(4, 36 + dataSize, Endian.little);
    buffer.setRange(8, 12, 'WAVE'.codeUnits);
    buffer.setRange(12, 16, 'fmt '.codeUnits);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    buffer.setRange(36, 40, 'data'.codeUnits);
    bd.setUint32(40, dataSize, Endian.little);

    final chordProgressions = <List<List<double>>>[
      [
        [110.0, 220.0, 261.63, 329.63, 493.88],
        [87.31, 174.61, 220.0, 261.63, 329.63],
        [130.81, 261.63, 329.63, 392.00, 493.88],
        [98.00, 196.00, 246.94, 293.66, 392.00],
      ],
      [
        [146.83, 293.66, 349.23, 440.00, 523.25],
        [98.00, 196.00, 246.94, 349.23, 440.00],
        [130.81, 261.63, 329.63, 392.00, 587.33],
        [110.0, 220.00, 261.63, 329.63, 392.00],
      ],
      [
        [82.41, 164.81, 246.94, 293.66, 369.99],
        [65.41, 130.81, 196.00, 246.94, 329.63],
        [73.42, 146.83, 220.00, 293.66, 369.99],
        [61.74, 123.47, 185.00, 220.00, 293.66],
      ],
      [
        [87.31, 174.61, 207.65, 261.63, 311.13],
        [69.30, 138.59, 207.65, 261.63, 349.23],
        [77.78, 155.56, 233.08, 293.66, 392.00],
        [65.41, 130.81, 196.00, 233.08, 311.13],
      ],
    ];

    final chords = chordProgressions[presetIndex % chordProgressions.length];
    final double bpm = 116.0 + (presetIndex * 8.0);
    final double beatSec = 60.0 / bpm;
    final double sixteenthSec = beatSec / 4.0;

    // 16-step rhythmic & melodic pattern (0 = musical rest / silence so wave ripples visibly drop and leap!)
    const List<int> melodyRhythmGate = [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0];
    const List<int> melodyNoteIndices = [0, 2, 4, 3, 1, 4, 2, 0, 3, 4, 2, 1, 4, 3, 1, 0];

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final int chordIdx = ((t / 6.0).floor()) % chords.length;
      final chord = chords[chordIdx];

      final int beatNum = (t / beatSec).floor();
      final double beatPhase = (t % beatSec) / beatSec;
      final int step16 = ((t / sixteenthSec).floor()) % 16;
      final double stepPhase = (t % sixteenthSec) / sixteenthSec;

      // 1. Punchy Sub-Bass Kick on beats 0, 2 (and syncopated 16th step 11)
      double kickSample = 0.0;
      if (beatNum % 2 == 0 || step16 == 11) {
        final double kickEnv = math.exp(-beatPhase * 11.0);
        final double kickFreq = 46.0 + 95.0 * math.exp(-beatPhase * 28.0);
        kickSample = math.sin(2.0 * math.pi * kickFreq * beatPhase) * kickEnv * 0.58;
      }

      // 2. Crisp Harmonic Snare / Clap on beats 1 and 3
      double snareSample = 0.0;
      if (beatNum % 2 == 1) {
        final double snareEnv = math.exp(-beatPhase * 16.0);
        final double body = math.sin(2.0 * math.pi * 185.0 * t) * 0.4;
        final double overtone =
            math.sin(2.0 * math.pi * 1420.0 * t + math.sin(t * 8900.0) * 2.5) * 0.6;
        snareSample = (body + overtone) * snareEnv * 0.36;
      }

      // 3. Breathing Chord Swell (pulsing with sidechain ducking on kick beats)
      final double sidechain = 1.0 - math.exp(-beatPhase * 6.0) * 0.78;
      double pad = 0.0;
      for (int c = 0; c < 3; c++) {
        final freq = chord[c];
        pad += math.sin(2.0 * math.pi * freq * t + c * 0.4) * 0.065 * sidechain;
      }

      // 4. Expressive Lead Melody with clear rests & pitch jumps
      double leadSample = 0.0;
      if (melodyRhythmGate[step16] == 1) {
        final int noteSlot = melodyNoteIndices[step16] % chord.length;
        final double noteFreq = chord[noteSlot] * (step16 % 3 == 0 ? 2.0 : 4.0);
        final double noteEnv = math.sin(math.min(1.0, stepPhase * 8.0) * math.pi * 0.5) *
            math.exp(-stepPhase * 3.8);
        leadSample = (math.sin(2.0 * math.pi * noteFreq * t) * 0.65 +
                math.sin(4.0 * math.pi * noteFreq * t) * 0.25 +
                math.sin(6.0 * math.pi * noteFreq * t) * 0.10) *
            noteEnv *
            0.38;
      }

      final double combined = (kickSample + snareSample + pad + leadSample).clamp(-0.96, 0.96);
      final int pcm16 = (combined * 32767.0).round();
      bd.setInt16(44 + i * 2, pcm16, Endian.little);
    }

    _cachedWavBytes[presetIndex] = buffer;
    return buffer;
  }
}
