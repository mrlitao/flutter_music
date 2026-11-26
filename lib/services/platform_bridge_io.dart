import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/track.dart';
import 'lrc_parser.dart';
import 'metadata_parser.dart';

/// Native IO implementation of [PlatformAudioBridge] for Windows, iOS, Android, and HarmonyOS NEXT.
/// Includes a non-blocking background Windows Media Foundation (`System.Windows.Media.MediaPlayer`)
/// engine so `.mp4`, `.m4a`, `.flac`, `.mp3`, `.wav`, `.aac`, `.wma` play smoothly with zero UI lag.
class PlatformAudioBridge {
  static const MethodChannel _nativeBridge = MethodChannel('com.auramusic/native_bridge');

  static const Set<String> supportedExtensions = {
    '.mp3',
    '.mp4',
    '.flac',
    '.wav',
    '.m4a',
    '.aac',
    '.ogg',
    '.wma',
  };

  _WindowsMediaFoundationDaemon? _winDaemon;
  bool _useWinDaemon = false;

  Future<_WindowsMediaFoundationDaemon> _ensureWinDaemon() async {
    _winDaemon ??= _WindowsMediaFoundationDaemon();
    await _winDaemon!.ensureStarted();
    return _winDaemon!;
  }

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

    if (!_useWinDaemon) {
      try {
        final res = await _nativeBridge.invokeMapMethod<String, dynamic>('play', {
          'path': playablePath,
          'positionMs': positionMs,
          'volume': volume,
          'speed': speed,
        });
        if (res != null) {
          final dur = res['durationMs'] as int?;
          final ok = (res['ok'] as bool?) ?? true;
          if (ok) {
            return (dur != null && dur > 500) ? dur : null;
          }
        }
      } catch (_) {
        // When running locally without C++ runner or if native channel fails, switch to Windows MF Daemon
        if (Platform.isWindows) {
          _useWinDaemon = true;
        }
      }
    }

    if (Platform.isWindows) {
      _useWinDaemon = true;
      final daemon = await _ensureWinDaemon();
      return daemon.play(
        path: playablePath,
        positionMs: positionMs,
        volume: volume,
        speed: speed,
      );
    }
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
    if (_useWinDaemon && Platform.isWindows) {
      _winDaemon?.pause();
      return;
    }
    try {
      await _nativeBridge.invokeMethod<void>('pause');
    } catch (_) {}
  }

  Future<void> stop() async {
    if (_useWinDaemon && Platform.isWindows) {
      _winDaemon?.stop();
      return;
    }
    try {
      await _nativeBridge.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> seek(int positionMs) async {
    if (_useWinDaemon && Platform.isWindows) {
      _winDaemon?.seek(positionMs);
      return;
    }
    try {
      await _nativeBridge.invokeMethod<void>('seek', {'positionMs': positionMs});
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    if (_useWinDaemon && Platform.isWindows) {
      _winDaemon?.setVolume(volume);
      return;
    }
    try {
      await _nativeBridge.invokeMethod<void>('setVolume', {'volume': volume});
    } catch (_) {}
  }

  Future<void> setSpeed(double speed) async {
    if (_useWinDaemon && Platform.isWindows) {
      _winDaemon?.setSpeed(speed);
      return;
    }
    try {
      await _nativeBridge.invokeMethod<void>('setSpeed', {'speed': speed});
    } catch (_) {}
  }

  Future<Map<String, int>?> getPositionAndDuration() async {
    if (_useWinDaemon && Platform.isWindows && _winDaemon != null) {
      return {
        'positionMs': _winDaemon!.latestPositionMs,
        'durationMs': _winDaemon!.latestDurationMs,
      };
    }
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

  File _getLibraryCacheFile() {
    String baseDir;
    try {
      if (Platform.isWindows) {
        baseDir = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      } else {
        baseDir = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      }
    } catch (_) {
      baseDir = Directory.systemTemp.path;
    }
    final appDir = Directory(p.join(baseDir, 'AuraMusic'));
    if (!appDir.existsSync()) {
      appDir.createSync(recursive: true);
    }
    return File(p.join(appDir.path, 'library_cache.json'));
  }

  /// Restores previously imported local tracks from `library_cache.json`.
  Future<List<Track>> loadSavedImportedTracks() async {
    try {
      final cacheFile = _getLibraryCacheFile();
      if (!await cacheFile.exists()) return const [];
      final raw = await cacheFile.readAsString();
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final restored = <Track>[];
      for (int i = 0; i < decoded.length; i++) {
        final item = decoded[i] as Map<String, dynamic>;
        final filePath = item['filePath'] as String? ?? '';
        if (filePath.isEmpty) continue;
        final file = File(filePath);
        if (!await file.exists()) continue;

        final parsed = await _parseIoFile(file, i);
        restored.add(
          parsed.copyWith(
            isFavorite: (item['isFavorite'] as bool?) ?? false,
            playCount: (item['playCount'] as int?) ?? 0,
            importedTimestampMs:
                (item['importedTimestampMs'] as int?) ?? parsed.importedTimestampMs,
          ),
        );
      }
      return restored;
    } catch (_) {
      return const [];
    }
  }

  /// Persists imported local tracks (non-built-in) to `library_cache.json`.
  Future<void> saveImportedTracks(List<Track> tracks) async {
    try {
      final cacheFile = _getLibraryCacheFile();
      final userTracks = tracks.where((t) => !t.isBuiltInDemo).toList();
      final payload = userTracks
          .map(
            (t) => {
              'filePath': t.filePath,
              'isFavorite': t.isFavorite,
              'playCount': t.playCount,
              'importedTimestampMs': t.importedTimestampMs,
            },
          )
          .toList();
      await cacheFile.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  Future<void> deleteSavedTrack(Track track) async {
    // Native deletion is persisted via saveImportedTracks() after removing from controller list
  }

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
          // For .mp4 / .m4a files whose 'moov'/'mvhd' atom is placed at the end of the file,
          // also read the trailing 256 KB if 'mvhd' wasn't found in the first 512 KB!
          final ext = p.extension(fileName).toLowerCase();
          if ((ext == '.mp4' || ext == '.m4a') &&
              fileSize > 512 * 1024 &&
              !_containsMvhd(headerBytes)) {
            final tailSize = math.min(256 * 1024, fileSize - maxRead);
            await raf.setPosition(fileSize - tailSize);
            final tailBytes = await raf.read(tailSize);
            final combined = Uint8List(headerBytes.length + tailBytes.length);
            combined.setRange(0, headerBytes.length, headerBytes);
            combined.setRange(headerBytes.length, combined.length, tailBytes);
            headerBytes = combined;
          }
        } finally {
          await raf.close();
        }
      }

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

  static bool _containsMvhd(Uint8List bytes) {
    for (int i = 0; i + 4 < bytes.length; i++) {
      if (bytes[i] == 0x6D &&
          bytes[i + 1] == 0x76 &&
          bytes[i + 2] == 0x68 &&
          bytes[i + 3] == 0x64) {
        return true;
      }
    }
    return false;
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

  void dispose() {
    _winDaemon?.dispose();
    _winDaemon = null;
  }
}

/// Persistent background Windows Media Foundation (`System.Windows.Media.MediaPlayer`) daemon.
/// Runs in its own process with a WPF Dispatcher pump so `.mp4`, `.m4a`, `.flac`, `.mp3`, `.wav`
/// play with hardware-accelerated audio and zero Flutter UI thread blocking.
class _WindowsMediaFoundationDaemon {
  Process? _process;
  int latestPositionMs = -1;
  int latestDurationMs = -1;
  String? _currentPath;
  bool _isStarting = false;
  bool _isDisposed = false;

  static const String _psScript = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName presentationCore
$player = New-Object System.Windows.Media.MediaPlayer
$isPlaying = $false
$currentFile = ""
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$reader = [Console]::In
$pendingTask = $reader.ReadLineAsync()

while ($true) {
  [System.Windows.Forms.Application]::DoEvents()
  [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

  if ($pendingTask.IsCompleted) {
    $line = $pendingTask.Result
    if ($null -eq $line) { break }
    $parts = $line.Split('|')
    $cmd = $parts[0]
    try {
      if ($cmd -eq 'PLAY') {
        $b64 = $parts[1]
        $posMs = [double]::Parse($parts[2])
        $vol = [double]::Parse($parts[3])
        $spd = [double]::Parse($parts[4])
        $path = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
        if ($currentFile -ne $path) {
          $player.Open([Uri]::new($path))
          $currentFile = $path
        }
        $player.Volume = $vol
        $player.SpeedRatio = $spd
        $player.Position = [TimeSpan]::FromMilliseconds($posMs)
        $player.Play()
        $isPlaying = $true
      } elseif ($cmd -eq 'PAUSE') {
        $player.Pause()
        $isPlaying = $false
      } elseif ($cmd -eq 'STOP') {
        $player.Stop()
        $isPlaying = $false
      } elseif ($cmd -eq 'SEEK') {
        $posMs = [double]::Parse($parts[1])
        $player.Position = [TimeSpan]::FromMilliseconds($posMs)
      } elseif ($cmd -eq 'VOL') {
        $player.Volume = [double]::Parse($parts[1])
      } elseif ($cmd -eq 'SPEED') {
        $player.SpeedRatio = [double]::Parse($parts[1])
      } elseif ($cmd -eq 'QUIT') {
        break
      }
    } catch {}
    $pendingTask = $reader.ReadLineAsync()
  }

  if ($isPlaying) {
    try {
      $pMs = [int]$player.Position.TotalMilliseconds
      $dMs = -1
      if ($player.NaturalDuration.HasTimeSpan) {
        $dMs = [int]$player.NaturalDuration.TimeSpan.TotalMilliseconds
      }
      [Console]::Out.WriteLine("POS|$pMs|$dMs")
      [Console]::Out.Flush()
    } catch {}
  }
  Start-Sleep -Milliseconds 60
}
$player.Close()
''';

  Future<void> ensureStarted() async {
    if (_process != null || _isStarting || _isDisposed) return;
    _isStarting = true;
    try {
      final proc = await Process.start(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', _psScript],
      );
      if (_isDisposed) {
        proc.kill();
        return;
      }
      _process = proc;
      proc.stdin.done.catchError((_) {});
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('POS|')) {
              final parts = line.split('|');
              if (parts.length >= 3) {
                latestPositionMs = int.tryParse(parts[1]) ?? latestPositionMs;
                final dur = int.tryParse(parts[2]) ?? -1;
                if (dur > 500) latestDurationMs = dur;
              }
            }
          });
    } catch (_) {
    } finally {
      _isStarting = false;
    }
  }

  void _sendCommand(String line) {
    if (_isDisposed) return;
    try {
      _process?.stdin.writeln(line);
    } catch (_) {}
  }

  Future<int?> play({
    required String path,
    required int positionMs,
    required double volume,
    required double speed,
  }) async {
    await ensureStarted();
    if (_isDisposed || _process == null) return null;

    if (_currentPath != path) {
      latestDurationMs = -1;
      _currentPath = path;
    }
    latestPositionMs = positionMs;
    final b64 = base64Encode(utf8.encode(path));
    _sendCommand('PLAY|$b64|$positionMs|${volume.toStringAsFixed(3)}|${speed.toStringAsFixed(2)}');
    return latestDurationMs > 500 ? latestDurationMs : null;
  }

  void pause() => _sendCommand('PAUSE');

  void stop() {
    _sendCommand('STOP');
    latestPositionMs = 0;
  }

  void seek(int positionMs) {
    latestPositionMs = positionMs;
    _sendCommand('SEEK|$positionMs');
  }

  void setVolume(double volume) => _sendCommand('VOL|${volume.toStringAsFixed(3)}');

  void setSpeed(double speed) => _sendCommand('SPEED|${speed.toStringAsFixed(2)}');

  void dispose() {
    _isDisposed = true;
    try {
      _process?.stdin.writeln('QUIT');
      _process?.kill();
    } catch (_) {}
    _process = null;
  }
}
