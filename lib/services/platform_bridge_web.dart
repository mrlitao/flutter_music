import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/track.dart';
import 'lrc_parser.dart';
import 'metadata_parser.dart';

/// Web (Chrome / Edge) implementation of [PlatformAudioBridge].
/// - Uses HTML5 `<audio>` + Web Audio `AnalyserNode` for real-time sound & FFT.
/// - Uses browser **IndexedDB (`AuraMusicDB`)** to persistently store imported local audio `Blob`s,
///   `.lrc` lyrics, play counts, and favorites so they survive browser restarts & can be deleted.
/// - Properly handles file/folder picker cancellation (`oncancel` + `window.onfocus` fallback) so
///   loading never gets stuck!
class PlatformAudioBridge {
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

  static const String _dbName = 'AuraMusicDB';
  static const String _storeName = 'imported_tracks';

  JSObject? _audioElement;
  JSObject? _audioContext;
  JSObject? _analyserNode;
  JSUint8Array? _freqDataArray;
  JSUint8Array? _timeDataArray;
  String? _currentSrc;
  final Map<int, String> _demoBlobUrls = {};

  void _ensureAudioEngineInitialized() {
    if (_audioElement != null) return;
    try {
      final audioCtor = globalContext['Audio'] as JSFunction?;
      if (audioCtor != null) {
        _audioElement = audioCtor.callAsConstructor<JSObject>();
        _audioElement!['preload'] = 'auto'.toJS;
      }
    } catch (_) {}
  }

  void _ensureWebAudioAnalyserConnected() {
    if (_analyserNode != null || _audioElement == null) return;
    try {
      final ctxCtor =
          (globalContext['AudioContext'] ?? globalContext['webkitAudioContext']) as JSFunction?;
      if (ctxCtor == null) return;

      _audioContext = ctxCtor.callAsConstructor<JSObject>();
      final source =
          _audioContext!.callMethod<JSObject>('createMediaElementSource'.toJS, _audioElement!);
      _analyserNode = _audioContext!.callMethod<JSObject>('createAnalyser'.toJS);
      _analyserNode!['fftSize'] = 512.toJS;
      _analyserNode!['minDecibels'] = (-85).toJS;
      _analyserNode!['maxDecibels'] = (-12).toJS;
      _analyserNode!['smoothingTimeConstant'] = 0.42.toJS;

      source.callMethod<JSAny?>('connect'.toJS, _analyserNode!);
      final destination = _audioContext!['destination'];
      _analyserNode!.callMethod<JSAny?>('connect'.toJS, destination);

      final binCount = (_analyserNode!['frequencyBinCount'] as JSNumber).toDartInt;
      final uint8Ctor = globalContext['Uint8Array'] as JSFunction;
      _freqDataArray = uint8Ctor.callAsConstructor<JSUint8Array>(binCount.toJS);
      _timeDataArray = uint8Ctor.callAsConstructor<JSUint8Array>(binCount.toJS);
    } catch (_) {}
  }

  String _getOrCreateDemoBlobUrl(int presetIndex, Uint8List wavBytes) {
    final existing = _demoBlobUrls[presetIndex];
    if (existing != null) return existing;

    final blobCtor = globalContext['Blob'] as JSFunction;
    final parts = <JSAny>[wavBytes.toJS].toJS;
    final options = JSObject();
    options['type'] = 'audio/wav'.toJS;
    final blob = blobCtor.callAsConstructor<JSObject>(parts, options);

    final urlObj = globalContext['URL'] as JSObject;
    final blobUrl = urlObj.callMethod<JSString>('createObjectURL'.toJS, blob).toDart;
    _demoBlobUrls[presetIndex] = blobUrl;
    return blobUrl;
  }

  Future<int?> play({
    required Track track,
    required Uint8List? demoWavBytes,
    required int positionMs,
    required double volume,
    required double speed,
  }) async {
    _ensureAudioEngineInitialized();
    final audio = _audioElement;
    if (audio == null) return null;

    _ensureWebAudioAnalyserConnected();

    try {
      if (_audioContext != null) {
        final state = (_audioContext!['state'] as JSString?)?.toDart;
        if (state == 'suspended') {
          _audioContext!.callMethod<JSAny?>('resume'.toJS);
        }
      }
    } catch (_) {}

    String srcUrl = track.filePath;
    if (track.isBuiltInDemo && demoWavBytes != null) {
      srcUrl = _getOrCreateDemoBlobUrl(track.demoPresetIndex, demoWavBytes);
    }

    try {
      if (_currentSrc != srcUrl) {
        audio['src'] = srcUrl.toJS;
        _currentSrc = srcUrl;
      }
      audio['volume'] = volume.clamp(0.0, 1.0).toJS;
      audio['playbackRate'] = speed.clamp(0.5, 2.0).toJS;

      try {
        audio['currentTime'] = (positionMs / 1000.0).toJS;
      } catch (_) {}

      final playPromise = audio.callMethod<JSObject?>('play'.toJS);
      if (playPromise != null) {
        await (playPromise as JSPromise).toDart;
      }

      final durNum = audio['duration'] as JSNumber?;
      if (durNum != null) {
        final durSec = durNum.toDartDouble;
        if (!durSec.isNaN && !durSec.isInfinite && durSec > 0.5) {
          return (durSec * 1000).round();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> pause() async {
    try {
      _audioElement?.callMethod<JSAny?>('pause'.toJS);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      _audioElement?.callMethod<JSAny?>('pause'.toJS);
      if (_audioElement != null) {
        _audioElement!['currentTime'] = 0.toJS;
      }
    } catch (_) {}
  }

  Future<void> seek(int positionMs) async {
    try {
      if (_audioElement != null) {
        _audioElement!['currentTime'] = (positionMs / 1000.0).toJS;
      }
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    try {
      if (_audioElement != null) {
        _audioElement!['volume'] = volume.clamp(0.0, 1.0).toJS;
      }
    } catch (_) {}
  }

  Future<void> setSpeed(double speed) async {
    try {
      if (_audioElement != null) {
        _audioElement!['playbackRate'] = speed.clamp(0.5, 2.0).toJS;
      }
    } catch (_) {}
  }

  Future<Map<String, int>?> getPositionAndDuration() async {
    final audio = _audioElement;
    if (audio == null) return null;
    try {
      final posNum = audio['currentTime'] as JSNumber?;
      final durNum = audio['duration'] as JSNumber?;
      final posSec = posNum?.toDartDouble ?? -1.0;
      final durSec = durNum?.toDartDouble ?? -1.0;
      return {
        'positionMs': (!posSec.isNaN && posSec >= 0) ? (posSec * 1000).round() : -1,
        'durationMs':
            (!durSec.isNaN && !durSec.isInfinite && durSec > 0) ? (durSec * 1000).round() : -1,
      };
    } catch (_) {
      return null;
    }
  }

  List<double>? getRealtimeFrequencyBins() {
    if (_analyserNode == null || _freqDataArray == null || _timeDataArray == null) return null;
    try {
      _analyserNode!.callMethod<JSAny?>('getByteFrequencyData'.toJS, _freqDataArray!);
      _analyserNode!.callMethod<JSAny?>('getByteTimeDomainData'.toJS, _timeDataArray!);

      final Uint8List freqBytes = _freqDataArray!.toDart;
      final Uint8List timeBytes = _timeDataArray!.toDart;
      final int len = freqBytes.length;
      if (len <= 0) return null;

      double rmsAcc = 0.0;
      int nonZeroFreqSum = 0;
      final int sampleCount = math.min(128, len);
      for (int i = 0; i < sampleCount; i++) {
        final int fVal = freqBytes[i];
        final int tVal = timeBytes[i];
        nonZeroFreqSum += fVal;
        final double centered = (tVal - 128) / 128.0;
        rmsAcc += centered * centered;
      }
      if (nonZeroFreqSum == 0) return null;

      final double rms = math.sqrt(rmsAcc / sampleCount).clamp(0.0, 1.0);
      final double rmsBoost = (0.55 + rms * 1.45).clamp(0.45, 1.85);

      final out = List<double>.filled(32, 0.02);
      for (int b = 0; b < 32; b++) {
        final int startBin = (math.pow(b / 32.0, 1.75) * 140).floor().clamp(1, len - 2);
        final int endBin = math.max(
          startBin + 1,
          (math.pow((b + 1) / 32.0, 1.75) * 140).floor().clamp(startBin + 1, len - 1),
        );
        double bandPeak = 0.0;
        for (int k = startBin; k < endBin; k++) {
          final double v = freqBytes[k] / 255.0;
          if (v > bandPeak) bandPeak = v;
        }
        final double contrasted = math.pow(bandPeak, 1.7).toDouble() * rmsBoost;
        out[b] = contrasted.clamp(0.02, 1.0);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // IndexedDB Persistence for Web Imported Audio Files
  // ===========================================================================
  Future<JSObject?> _openDb() async {
    final completer = Completer<JSObject?>();
    try {
      final idb = globalContext['indexedDB'] as JSObject?;
      if (idb == null) {
        return null;
      }
      final req = idb.callMethod<JSObject>('open'.toJS, _dbName.toJS, 1.toJS);

      req['onupgradeneeded'] = ((JSObject event) {
        try {
          final target = event['target'] as JSObject;
          final db = target['result'] as JSObject;
          final storeNames = db['objectStoreNames'] as JSObject;
          final contains =
              (storeNames.callMethod<JSBoolean>('contains'.toJS, _storeName.toJS)).toDart;
          if (!contains) {
            final opts = JSObject();
            opts['keyPath'] = 'id'.toJS;
            db.callMethod<JSAny?>('createObjectStore'.toJS, _storeName.toJS, opts);
          }
        } catch (_) {}
      }).toJS;

      req['onsuccess'] = ((JSObject event) {
        final target = event['target'] as JSObject;
        if (!completer.isCompleted) {
          completer.complete(target['result'] as JSObject?);
        }
      }).toJS;

      req['onerror'] = ((JSAny? _) {
        if (!completer.isCompleted) completer.complete(null);
      }).toJS;
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  Future<void> _putRecordToIndexedDb({
    required String id,
    required String fileName,
    required String folderPath,
    required int fileSize,
    required int importedTimestampMs,
    required JSObject audioBlob,
    Uint8List? lrcBytes,
  }) async {
    final db = await _openDb();
    if (db == null) return;
    final completer = Completer<void>();
    try {
      final tx = db.callMethod<JSObject>('transaction'.toJS, _storeName.toJS, 'readwrite'.toJS);
      final store = tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
      final record = JSObject();
      record['id'] = id.toJS;
      record['fileName'] = fileName.toJS;
      record['folderPath'] = folderPath.toJS;
      record['fileSize'] = fileSize.toJS;
      record['importedTimestampMs'] = importedTimestampMs.toJS;
      record['playCount'] = 0.toJS;
      record['isFavorite'] = false.toJS;
      record['audioBlob'] = audioBlob;
      if (lrcBytes != null && lrcBytes.isNotEmpty) {
        record['lrcBytes'] = lrcBytes.toJS;
      }
      store.callMethod<JSAny?>('put'.toJS, record);

      tx['oncomplete'] = ((JSAny? _) {
        if (!completer.isCompleted) completer.complete();
      }).toJS;
      tx['onerror'] = ((JSAny? _) {
        if (!completer.isCompleted) completer.complete();
      }).toJS;
      await completer.future;
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Restores previously imported local music files from Chrome's IndexedDB (`AuraMusicDB`).
  Future<List<Track>> loadSavedImportedTracks() async {
    final db = await _openDb();
    if (db == null) return const [];

    final completer = Completer<List<JSObject>>();
    try {
      final tx = db.callMethod<JSObject>('transaction'.toJS, _storeName.toJS, 'readonly'.toJS);
      final store = tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
      final req = store.callMethod<JSObject>('getAll'.toJS);
      req['onsuccess'] = ((JSAny? _) {
        final res = req['result'] as JSArray?;
        if (res != null) {
          completer.complete(res.toDart.cast<JSObject>());
        } else {
          completer.complete(const []);
        }
      }).toJS;
      req['onerror'] = ((JSAny? _) {
        if (!completer.isCompleted) completer.complete(const []);
      }).toJS;
    } catch (_) {
      if (!completer.isCompleted) completer.complete(const []);
    }

    final records = await completer.future;
    if (records.isEmpty) return const [];

    final urlObj = globalContext['URL'] as JSObject;
    final restored = <Track>[];

    for (int i = 0; i < records.length; i++) {
      try {
        final rec = records[i];
        final id = (rec['id'] as JSString).toDart;
        final fileName = (rec['fileName'] as JSString).toDart;
        final folderPath = (rec['folderPath'] as JSString).toDart;
        final fileSize = (rec['fileSize'] as JSNumber).toDartInt;
        final importedMs = (rec['importedTimestampMs'] as JSNumber?)?.toDartInt ?? 0;
        final playCount = (rec['playCount'] as JSNumber?)?.toDartInt ?? 0;
        final isFavorite = (rec['isFavorite'] as JSBoolean?)?.toDart ?? false;
        final audioBlob = rec['audioBlob'] as JSObject;

        final sliceEnd = math.min(fileSize, 512 * 1024);
        final headerBlob = audioBlob.callMethod<JSObject>('slice'.toJS, 0.toJS, sliceEnd.toJS);
        final buf = (await (headerBlob.callMethod<JSPromise>('arrayBuffer'.toJS)).toDart)
            as JSArrayBuffer;
        final headerBytes = buf.toDart.asUint8List();

        List<LyricLine> companionLyrics = const [];
        final lrcJs = rec['lrcBytes'] as JSUint8Array?;
        if (lrcJs != null) {
          companionLyrics = LrcParser.parseBytes(lrcJs.toDart);
        }

        final blobUrl = urlObj.callMethod<JSString>('createObjectURL'.toJS, audioBlob).toDart;

        final track = AudioMetadataParser.parseBytes(
          id: id,
          filePath: blobUrl,
          fileName: fileName,
          folderPath: folderPath,
          fileSize: fileSize,
          headerBytes: headerBytes,
          companionLyrics: companionLyrics,
          indexSeed: i,
        ).copyWith(
          importedTimestampMs: importedMs,
          playCount: playCount,
          isFavorite: isFavorite,
        );
        restored.add(track);
      } catch (_) {}
    }

    return restored;
  }

  /// Syncs updated favorite / playCount states back to IndexedDB.
  Future<void> saveImportedTracks(List<Track> tracks) async {
    final db = await _openDb();
    if (db == null) return;
    for (final track in tracks.where((t) => !t.isBuiltInDemo)) {
      try {
        final tx = db.callMethod<JSObject>('transaction'.toJS, _storeName.toJS, 'readwrite'.toJS);
        final store = tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
        final req = store.callMethod<JSObject>('get'.toJS, track.id.toJS);
        req['onsuccess'] = ((JSAny? _) {
          final existing = req['result'] as JSObject?;
          if (existing != null) {
            existing['playCount'] = track.playCount.toJS;
            existing['isFavorite'] = track.isFavorite.toJS;
            store.callMethod<JSAny?>('put'.toJS, existing);
          }
        }).toJS;
      } catch (_) {}
    }
  }

  /// Deletes an imported track from IndexedDB and revokes its Blob URL.
  Future<void> deleteSavedTrack(Track track) async {
    try {
      if (track.filePath.startsWith('blob:')) {
        final urlObj = globalContext['URL'] as JSObject;
        urlObj.callMethod<JSAny?>('revokeObjectURL'.toJS, track.filePath.toJS);
      }
      final db = await _openDb();
      if (db == null) return;
      final tx = db.callMethod<JSObject>('transaction'.toJS, _storeName.toJS, 'readwrite'.toJS);
      final store = tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
      store.callMethod<JSAny?>('delete'.toJS, track.id.toJS);
    } catch (_) {}
  }

  Future<Uint8List?> loadWavBytesForFft(Track track) async => null;

  Future<List<Track>> scanDefaultDirectories() async => const [];

  Future<List<Track>> scanCustomDirectory(String directoryPath) async {
    return pickFolderAndScan();
  }

  Future<List<Track>> pickFolderAndScan() async {
    return _pickBrowserFiles(directoryMode: true);
  }

  Future<List<Track>> pickAudioFiles() async {
    return _pickBrowserFiles(directoryMode: false);
  }

  /// Opens browser file/folder picker with proper cancel detection (`oncancel` + `window.onfocus`)
  /// so cancelling the OS dialog NEVER leaves the UI stuck in loading state!
  Future<List<Track>> _pickBrowserFiles({required bool directoryMode}) async {
    final completer = Completer<List<Track>>();
    bool fileSelected = false;
    Timer? cancelFallbackTimer;

    try {
      final doc = globalContext['document'] as JSObject;
      final win = globalContext['window'] as JSObject;
      final input = doc.callMethod<JSObject>('createElement'.toJS, 'input'.toJS);
      input['type'] = 'file'.toJS;
      input['multiple'] = true.toJS;
      input['style'] = 'display:none'.toJS;

      if (directoryMode) {
        input['webkitdirectory'] = true.toJS;
        input['directory'] = true.toJS;
      } else {
        input['accept'] = 'audio/*,video/mp4,.mp3,.mp4,.flac,.wav,.m4a,.aac,.ogg,.wma,.lrc'.toJS;
      }

      void cleanup() {
        cancelFallbackTimer?.cancel();
        try {
          input.callMethod<JSAny?>('remove'.toJS);
        } catch (_) {}
      }

      input['onchange'] = ((JSAny? _) {
        fileSelected = true;
        cleanup();
        unawaited(_handleSelectedFiles(input, completer));
      }).toJS;

      input['oncancel'] = ((JSAny? _) {
        cleanup();
        if (!completer.isCompleted) completer.complete(const []);
      }).toJS;

      late JSFunction onFocusListener;
      onFocusListener = ((JSAny? _) {
        win.callMethod<JSAny?>('removeEventListener'.toJS, 'focus'.toJS, onFocusListener);
        cancelFallbackTimer = Timer(const Duration(milliseconds: 500), () {
          if (!fileSelected && !completer.isCompleted) {
            cleanup();
            completer.complete(const []);
          }
        });
      }).toJS;

      win.callMethod<JSAny?>('addEventListener'.toJS, 'focus'.toJS, onFocusListener);

      final body = doc['body'] as JSObject?;
      body?.callMethod<JSAny?>('appendChild'.toJS, input);
      input.callMethod<JSAny?>('click'.toJS);
    } catch (_) {
      cancelFallbackTimer?.cancel();
      if (!completer.isCompleted) completer.complete(const []);
    }
    return completer.future;
  }

  Future<void> _handleSelectedFiles(JSObject input, Completer<List<Track>> completer) async {
    try {
      final filesList = input['files'] as JSObject?;
      if (filesList == null) {
        if (!completer.isCompleted) completer.complete(const []);
        return;
      }
      final length = (filesList['length'] as JSNumber).toDartInt;
      final audioFileObjects = <JSObject>[];
      final lrcFileMap = <String, JSObject>{};

      for (int i = 0; i < length; i++) {
        final file = filesList.callMethod<JSObject>('item'.toJS, i.toJS);
        final name = (file['name'] as JSString).toDart;
        final ext = p.extension(name).toLowerCase();
        if (ext == '.lrc') {
          lrcFileMap[p.basenameWithoutExtension(name).toLowerCase()] = file;
        } else if (supportedExtensions.contains(ext)) {
          audioFileObjects.add(file);
        }
      }

      final urlObj = globalContext['URL'] as JSObject;
      final parsedTracks = <Track>[];
      final maxTracks = math.min(audioFileObjects.length, 250);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < maxTracks; i++) {
        final file = audioFileObjects[i];
        final name = (file['name'] as JSString).toDart;
        final size = (file['size'] as JSNumber).toDartInt;
        final relPath = ((file['webkitRelativePath'] as JSString?)?.toDart ?? '').trim();
        final folderName = relPath.isNotEmpty && relPath.contains('/')
            ? relPath.split('/').first
            : '本机浏览器导入音乐';

        final sliceEnd = math.min(size, 512 * 1024);
        final headerBlob = file.callMethod<JSObject>('slice'.toJS, 0.toJS, sliceEnd.toJS);
        final arrayBufPromise = headerBlob.callMethod<JSPromise>('arrayBuffer'.toJS);
        final arrayBuf = (await arrayBufPromise.toDart) as JSArrayBuffer;
        final headerBytes = arrayBuf.toDart.asUint8List();

        List<LyricLine> companionLyrics = const [];
        Uint8List? lrcRawBytes;
        final baseKey = p.basenameWithoutExtension(name).toLowerCase();
        final lrcFile = lrcFileMap[baseKey];
        if (lrcFile != null) {
          final lrcBufPromise = lrcFile.callMethod<JSPromise>('arrayBuffer'.toJS);
          final lrcBuf = (await lrcBufPromise.toDart) as JSArrayBuffer;
          lrcRawBytes = lrcBuf.toDart.asUint8List();
          companionLyrics = LrcParser.parseBytes(lrcRawBytes);
        }

        // Stable persistent ID for IndexedDB deduplication across sessions
        final stableId = 'web_idb_${folderName}_${name}_$size';
        final blobUrl = urlObj.callMethod<JSString>('createObjectURL'.toJS, file).toDart;

        await _putRecordToIndexedDb(
          id: stableId,
          fileName: name,
          folderPath: folderName,
          fileSize: size,
          importedTimestampMs: nowMs + i,
          audioBlob: file,
          lrcBytes: lrcRawBytes,
        );

        final track = AudioMetadataParser.parseBytes(
          id: stableId,
          filePath: blobUrl,
          fileName: name,
          folderPath: folderName,
          fileSize: size,
          headerBytes: headerBytes,
          companionLyrics: companionLyrics,
          indexSeed: i,
        ).copyWith(importedTimestampMs: nowMs + i);

        parsedTracks.add(track);
      }

      if (!completer.isCompleted) completer.complete(parsedTracks);
    } catch (_) {
      if (!completer.isCompleted) completer.complete(const []);
    }
  }

  void dispose() {
    try {
      _audioElement?.callMethod<JSAny?>('pause'.toJS);
    } catch (_) {}
  }
}
