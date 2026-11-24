import '../models/track.dart';
import 'platform_bridge.dart';

/// Cross-platform façade for scanning local music across Native IO and Web.
class LocalMusicScanner {
  static final PlatformAudioBridge _bridge = PlatformAudioBridge();

  static Future<List<Track>> scanDefaultDirectories() => _bridge.scanDefaultDirectories();

  static Future<List<Track>> scanCustomDirectory(String directoryPath) =>
      _bridge.scanCustomDirectory(directoryPath);

  static Future<List<Track>> pickFolderAndScan() => _bridge.pickFolderAndScan();

  static Future<List<Track>> pickAudioFiles() => _bridge.pickAudioFiles();
}
