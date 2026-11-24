import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/track.dart';
import 'lrc_parser.dart';
import 'metadata_parser.dart';

/// Native IO implementation of [PlatformAudioBridge] for Windows, iOS, Android, and HarmonyOS NEXT.
class PlatformAudioBridge {
  static const MethodChannel _nativeBridge = MethodChannel('com.auramusic/native_bridge');

  static const Set<String> supportedExtensions = {
    '.mp3',
    '.flac',
    '.wav',
    '.m4a',
    '.aac',
    '.ogg',
    '.wma',
  };

  Future<int?> play({
    required Track track,
    required Uint8List? demoWavBytes,
    required int positionMs,
    required double volume,
    required double speed,
  }) async {
    String playablePath = track.filePath;
    if (track.isBuiltInDemo && demoWavBytes != null) {
      playablePath = await _ensureWavOnDisk(track.demoPresetIndex, demoWavBytes);
    }

    try {
      final res = await _nativeBridge.invokeMapMethod<String, dynamic>('play', {
        'path': playablePath,
        'positionMs': positionMs,
        'volume': volume,
      });
      if (res != null && res['durationMs'] is int && (res['durationMs'] as int) > 500) {
        return res['durationMs'] as int;
      }
    } catch (_) {}
    return null;
  }

  Future<String> _ensureWavOnDisk(int presetIndex, Uint8List wavBytes) async {
    try {
      final tempDir = Directory.systemTemp;
      final outPath = p.join(tempDir.path, 'auramusic_synth_track_$presetIndex.wav');
      final file = File(outPath);
      if (!await file.exists() || (await file.length()) != wavBytes.length) {
        await file.writeAsBytes(wavBytes, flush: true);
      }
      return outPath;
    } catch (_) {
      return 'builtin://demo_$presetIndex.wav';
    }
  }

  Future<void> pause() async {
    try {
      await _nativeBridge.invokeMethod<void>('pause');
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _nativeBridge.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> seek(int positionMs) async {
    try {
      await _nativeBridge.invokeMethod<void>('seek', {'positionMs': positionMs});
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    try {
      await _nativeBridge.invokeMethod<void>('setVolume', {'volume': volume});
    } catch (_) {}
  }

  Future<void> setSpeed(double speed) async {}

  Future<Map<String, int>?> getPositionAndDuration() async {
    try {
      final res = await _nativeBridge.invokeMapMethod<String, dynamic>('getPosition');
      if (res != null) {
        return {
          'positionMs': (res['positionMs'] as int?) ?? -1,
          'durationMs': (res['durationMs'] as int?) ?? -1,
        };
      }
    } catch (_) {}
    return null;
  }

  List<double>? getRealtimeFrequencyBins() => null;

  Future<Uint8List?> loadWavBytesForFft(Track track) async {
    if (!track.filePath.toLowerCase().endsWith('.wav')) return null;
    try {
      final file = File(track.filePath);
      if (await file.exists()) {
        final len = await file.length();
        if (len > 44 && len <= 25 * 1024 * 1024) {
          return await file.readAsBytes();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<Track>> scanDefaultDirectories() async {
    final dirs = _getDefaultMusicDirectories();
    final allFound = <Track>[];
    for (final dir in dirs) {
      final found = await scanCustomDirectory(dir, maxFiles: 100);
      allFound.addAll(found);
    }
    return allFound;
  }

  Future<List<Track>> scanCustomDirectory(String directoryPath, {int maxFiles = 250}) async {
    final results = <Track>[];
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return results;

    final audioFiles = <File>[];
    await _collectAudioFiles(dir, audioFiles, currentDepth: 0, maxDepth: 2, maxFiles: maxFiles);

    int seed = 0;
    for (final file in audioFiles) {
      final track = await _parseIoFile(file, seed++);
      results.add(track);
    }
    return results;
  }

  Future<List<Track>> pickFolderAndScan() async {
    try {
      final folderPath = await _nativeBridge.invokeMethod<String>('pickFolder');
      if (folderPath != null && folderPath.trim().isNotEmpty) {
        return await scanCustomDirectory(folderPath.trim());
      }
    } catch (_) {}
    return const [];
  }

  Future<List<Track>> pickAudioFiles() async {
    try {
      final rawList = await _nativeBridge.invokeMethod<List<dynamic>>('pickAudioFiles');
      if (rawList != null && rawList.isNotEmpty) {
        final paths = rawList.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        final results = <Track>[];
        int seed = 0;
        for (final filePath in paths) {
          final ext = p.extension(filePath).toLowerCase();
          if (!supportedExtensions.contains(ext)) continue;
          final file = File(filePath);
          if (await file.exists()) {
            results.add(await _parseIoFile(file, seed++));
          }
        }
        return results;
      }
    } catch (_) {}
    return const [];
  }

  Future<Track> _parseIoFile(File file, int indexSeed) async {
    final filePath = file.path;
    final folderPath = p.dirname(filePath);
    final fileName = p.basename(filePath);
    int fileSize = 0;
    Uint8List headerBytes = Uint8List(0);
    List<LyricLine> companionLyrics = const [];

    try {
      final stat = await file.stat();
      fileSize = stat.size;
      final maxRead = math.min(fileSize, 512 * 1024);
      if (maxRead > 16) {
        final raf = await file.open(mode: FileMode.read);
        try {
          headerBytes = await raf.read(maxRead);
        } finally {
          await raf.close();
        }
      }

      // Check for companion .lrc file alongside audio file
      final baseName = p.basenameWithoutExtension(filePath);
      final lrcFile = File(p.join(folderPath, '$baseName.lrc'));
      if (await lrcFile.exists()) {
        final lrcBytes = await lrcFile.readAsBytes();
        companionLyrics = LrcParser.parseBytes(lrcBytes);
      }
    } catch (_) {}

    return AudioMetadataParser.parseBytes(
      id: filePath,
      filePath: filePath,
      fileName: fileName,
      folderPath: folderPath,
      fileSize: fileSize,
      headerBytes: headerBytes,
      companionLyrics: companionLyrics,
      indexSeed: indexSeed,
    );
  }

  List<String> _getDefaultMusicDirectories() {
    final dirs = <String>[];
    try {
      final env = Platform.environment;
      if (Platform.isWindows) {
        final userProfile = env['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          dirs.add(p.join(userProfile, 'Music'));
          dirs.add(p.join(userProfile, 'Downloads'));
        }
      } else if (Platform.isAndroid) {
        dirs.addAll([
          '/storage/emulated/0/Music',
          '/storage/emulated/0/Download',
          '/sdcard/Music',
        ]);
      } else if (Platform.isIOS || Platform.isMacOS) {
        final home = env['HOME'];
        if (home != null && home.isNotEmpty) {
          dirs.add(p.join(home, 'Documents'));
          dirs.add(p.join(home, 'Music'));
        }
      } else {
        dirs.addAll([
          '/storage/Users/currentUser/Music',
          '/storage/Users/currentUser/Download',
          '/data/storage/el2/base/haps/entry/files',
        ]);
      }
    } catch (_) {}
    return dirs;
  }

  Future<void> _collectAudioFiles(
    Directory dir,
    List<File> out, {
    required int currentDepth,
    required int maxDepth,
    required int maxFiles,
  }) async {
    if (out.length >= maxFiles || currentDepth > maxDepth) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (out.length >= maxFiles) break;
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (supportedExtensions.contains(ext)) {
            out.add(entity);
          }
        } else if (entity is Directory && currentDepth < maxDepth) {
          final name = p.basename(entity.path);
          if (!name.startsWith('.') && !name.startsWith(r'$')) {
            await _collectAudioFiles(
              entity,
              out,
              currentDepth: currentDepth + 1,
              maxDepth: maxDepth,
              maxFiles: maxFiles,
            );
          }
        }
      }
    } catch (_) {}
  }

  void dispose() {}
}
