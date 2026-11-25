import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';

/// Supported playback loop / shuffle modes.
enum PlayMode {
  sequence('列表循环', Icons.repeat_rounded),
  singleLoop('单曲循环', Icons.repeat_one_rounded),
  shuffle('随机播放', Icons.shuffle_rounded);

  const PlayMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 8 sorting options for Local Songs (导入时间正倒序、名称正倒序、歌手名称正倒序、播放次数正倒序).
enum TrackSortOption {
  importTimeAsc('导入时间正序', '最早导入优先', Icons.arrow_upward_rounded),
  importTimeDesc('导入时间倒序', '最新导入优先', Icons.arrow_downward_rounded),
  titleAsc('名称正序', 'A → Z', Icons.sort_by_alpha_rounded),
  titleDesc('名称倒序', 'Z → A', Icons.sort_by_alpha_rounded),
  artistAsc('歌手名称正序', 'A → Z', Icons.person_outline_rounded),
  artistDesc('歌手名称倒序', 'Z → A', Icons.person_rounded),
  playCountAsc('播放次数正序', '最少播放 → 最多', Icons.bar_chart_rounded),
  playCountDesc('播放次数倒序', '最多播放 → 最少', Icons.local_fire_department_rounded);

  const TrackSortOption(this.label, this.subtitle, this.icon);
  final String label;
  final String subtitle;
  final IconData icon;
}

/// Visual theme presets for the Dynamic Frosted Glass (AuraGlass) system.
enum VisualThemePreset {
  dynamicCover(
    name: '封面极光 (自适应)',
    primary: Color(0xFF06B6D4),
    secondary: Color(0xFFD946EF),
    tertiary: Color(0xFF6366F1),
    surfaceBase: Color(0xFF090D18),
  ),
  auroraNeon(
    name: '极光紫青',
    primary: Color(0xFF22D3EE),
    secondary: Color(0xFFE879F9),
    tertiary: Color(0xFF818CF8),
    surfaceBase: Color(0xFF080B14),
  ),
  sunsetGold(
    name: '落日流金',
    primary: Color(0xFFFBBF24),
    secondary: Color(0xFFF43F5E),
    tertiary: Color(0xFFEC4899),
    surfaceBase: Color(0xFF14090E),
  ),
  emeraldDeep(
    name: '深海翡翠',
    primary: Color(0xFF34D399),
    secondary: Color(0xFF06B6D4),
    tertiary: Color(0xFF3B82F6),
    surfaceBase: Color(0xFF061214),
  ),
  cyberRose(
    name: '赛博绯红',
    primary: Color(0xFFFF2E93),
    secondary: Color(0xFF7928CA),
    tertiary: Color(0xFF00DF89),
    surfaceBase: Color(0xFF0F0718),
  );

  const VisualThemePreset({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.surfaceBase,
  });

  final String name;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color surfaceBase;
}

/// A single synchronized lyric line parsed from LRC or embedded tags.
class LyricLine {
  const LyricLine({
    required this.timestamp,
    required this.text,
    this.translation,
  });

  final Duration timestamp;
  final String text;
  final String? translation;
}

/// Equalizer frequency band configuration.
class EqualizerBand {
  const EqualizerBand({
    required this.label,
    required this.frequencyHz,
    this.gainDb = 0.0,
  });

  final String label;
  final int frequencyHz;
  final double gainDb;

  EqualizerBand copyWith({double? gainDb}) {
    return EqualizerBand(
      label: label,
      frequencyHz: frequencyHz,
      gainDb: gainDb ?? this.gainDb,
    );
  }
}

/// Real-time acoustic spectrum snapshot driving the Fluid Streamline Wave Ripple.
class SpectrumFrame {
  const SpectrumFrame({
    required this.bassEnergy,
    required this.midEnergy,
    required this.trebleEnergy,
    required this.beatPulse,
    required this.bins,
    required this.phase,
    required this.pitchClasses,
    required this.pitchTrail1,
    required this.pitchTrail2,
  });

  factory SpectrumFrame.idle([double phase = 0.0]) {
    final idlePitch = List<double>.filled(12, 0.02);
    return SpectrumFrame(
      bassEnergy: 0.04,
      midEnergy: 0.04,
      trebleEnergy: 0.03,
      beatPulse: 0.0,
      bins: List<double>.filled(32, 0.03),
      phase: phase,
      pitchClasses: idlePitch,
      pitchTrail1: idlePitch,
      pitchTrail2: idlePitch,
    );
  }

  final double bassEnergy;
  final double midEnergy;
  final double trebleEnergy;
  final double beatPulse;
  final List<double> bins;
  final double phase;

  /// 12 chromatic pitch classes (C, C#, D, D#, E, F, F#, G, G#, A, A#, B) mapped to fixed angles.
  final List<double> pitchClasses;

  /// Delayed pitch-class energy (~80ms & ~160ms) for radial outward streamline ripple diffusion.
  final List<double> pitchTrail1;
  final List<double> pitchTrail2;
}

/// Represents a local or synthesized music track in the library.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    required this.duration,
    required this.formatBadge,
    required this.folderPath,
    this.bitrateKbps = 320,
    this.sampleRateHz = 44100,
    this.bitDepth = 16,
    this.fileSize = 0,
    this.coverBytes,
    this.paletteColors = const [
      Color(0xFF06B6D4),
      Color(0xFFD946EF),
      Color(0xFF6366F1),
    ],
    this.lyrics = const [],
    this.isFavorite = false,
    this.isBuiltInDemo = false,
    this.demoPresetIndex = 0,
    this.importedTimestampMs = 0,
    this.playCount = 0,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final Duration duration;
  final String formatBadge;
  final String folderPath;
  final int bitrateKbps;
  final int sampleRateHz;
  final int bitDepth;
  final int fileSize;
  final Uint8List? coverBytes;
  final List<Color> paletteColors;
  final List<LyricLine> lyrics;
  final bool isFavorite;
  final bool isBuiltInDemo;
  final int demoPresetIndex;

  /// Monotonic timestamp (ms) when the track was imported into the library.
  final int importedTimestampMs;

  /// Total number of times this track has been played.
  final int playCount;

  Color get primaryColor =>
      paletteColors.isNotEmpty ? paletteColors[0] : const Color(0xFF06B6D4);
  Color get secondaryColor =>
      paletteColors.length > 1 ? paletteColors[1] : const Color(0xFFD946EF);
  Color get tertiaryColor =>
      paletteColors.length > 2 ? paletteColors[2] : const Color(0xFF6366F1);

  String get formattedDuration {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    String? filePath,
    Duration? duration,
    String? formatBadge,
    Uint8List? coverBytes,
    List<Color>? paletteColors,
    List<LyricLine>? lyrics,
    bool? isFavorite,
    int? importedTimestampMs,
    int? playCount,
  }) {
    return Track(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      filePath: filePath ?? this.filePath,
      duration: duration ?? this.duration,
      formatBadge: formatBadge ?? this.formatBadge,
      folderPath: folderPath,
      bitrateKbps: bitrateKbps,
      sampleRateHz: sampleRateHz,
      bitDepth: bitDepth,
      fileSize: fileSize,
      coverBytes: coverBytes ?? this.coverBytes,
      paletteColors: paletteColors ?? this.paletteColors,
      lyrics: lyrics ?? this.lyrics,
      isFavorite: isFavorite ?? this.isFavorite,
      isBuiltInDemo: isBuiltInDemo,
      demoPresetIndex: demoPresetIndex,
      importedTimestampMs: importedTimestampMs ?? this.importedTimestampMs,
      playCount: playCount ?? this.playCount,
    );
  }
}
