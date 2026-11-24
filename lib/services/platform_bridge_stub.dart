import 'dart:typed_data';
import '../models/track.dart';

/// Unified platform bridge interface across Native IO (Windows/iOS/Android/HarmonyOS) and Web (Chrome/Edge).
class PlatformAudioBridge {
  Future<int?> play({
    required Track track,
    required Uint8List? demoWavBytes,
    required int positionMs,
    required double volume,
    required double speed,
  }) async =>
      null;

  Future<void> pause() async {}

  Future<void> stop() async {}

  Future<void> seek(int positionMs) async {}

  Future<void> setVolume(double volume) async {}

  Future<void> setSpeed(double speed) async {}

  Future<Map<String, int>?> getPositionAndDuration() async => null;

  List<double>? getRealtimeFrequencyBins() => null;

  Future<List<Track>> scanDefaultDirectories() async => const [];

  Future<List<Track>> scanCustomDirectory(String directoryPath) async => const [];

  Future<List<Track>> pickFolderAndScan() async => const [];

  Future<List<Track>> pickAudioFiles() async => const [];

  Future<Uint8List?> loadWavBytesForFft(Track track) async => null;

  void dispose() {}
}
