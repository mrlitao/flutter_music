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
/// Uses HTML5 `<audio>` + Web Audio API `AnalyserNode` (both frequency & time-domain data)
/// for real-time melody/rhythm extraction and sound playback.
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
        // Note: Do NOT set crossOrigin = 'anonymous' on local blob: URLs,
        // as some Chromium builds zero out MediaElementAudioSourceNode on blob URLs with crossOrigin set.
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
      // Higher FFT resolution (512 -> 256 frequency bins) + fast response (low smoothingTimeConstant)
      // so every melody note and drum transient jumps crisply without lag!
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

      if (positionMs > 0) {
        try {
          audio['currentTime'] = (positionMs / 1000.0).toJS;
        } catch (_) {}
      }

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

  /// Reads real-time 32-band FFT frequency + time-domain RMS envelope directly from Chrome's Web Audio `AnalyserNode`!
  List<double>? getRealtimeFrequencyBins() {
    if (_analyserNode == null || _freqDataArray == null || _timeDataArray == null) return null;
    try {
      _analyserNode!.callMethod<JSAny?>('getByteFrequencyData'.toJS, _freqDataArray!);
      _analyserNode!.callMethod<JSAny?>('getByteTimeDomainData'.toJS, _timeDataArray!);

      final Uint8List freqBytes = _freqDataArray!.toDart;
      final Uint8List timeBytes = _timeDataArray!.toDart;
      final int len = freqBytes.length;
      if (len <= 0) return null;

      // Compute real-time waveform RMS amplitude from time-domain samples (centered at 128)
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
      // Dynamic envelope gate: boosts musical peaks and suppresses flat background hum
      final double rmsBoost = (0.55 + rms * 1.45).clamp(0.45, 1.85);

      // Map logarithmic musical frequency sub-bands (from 40Hz sub-bass to 10kHz treble) into 32 bins
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
        // Apply non-linear contrast curve (pow 1.7) so quiet passages stay calm
        // and melody notes / beats jump sharply!
        final double contrasted = math.pow(bandPeak, 1.7).toDouble() * rmsBoost;
        out[b] = contrasted.clamp(0.02, 1.0);
      }
      return out;
    } catch (_) {
      return null;
    }
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

  Future<List<Track>> _pickBrowserFiles({required bool directoryMode}) async {
    final completer = Completer<List<Track>>();
    try {
      final doc = globalContext['document'] as JSObject;
      final input = doc.callMethod<JSObject>('createElement'.toJS, 'input'.toJS);
      input['type'] = 'file'.toJS;
      input['multiple'] = true.toJS;

      if (directoryMode) {
        input['webkitdirectory'] = true.toJS;
        input['directory'] = true.toJS;
      } else {
        input['accept'] = 'audio/*,video/mp4,.mp3,.mp4,.flac,.wav,.m4a,.aac,.ogg,.wma,.lrc'.toJS;
      }

      input['onchange'] = ((JSAny? _) {
        unawaited(_handleSelectedFiles(input, completer));
      }).toJS;

      input.callMethod<JSAny?>('click'.toJS);
    } catch (_) {
      if (!completer.isCompleted) completer.complete(const []);
    }
    return completer.future;
  }

  Future<void> _handleSelectedFiles(JSObject input, Completer<List<Track>> completer) async {
    try {
      final filesList = input['files'] as JSObject?;
      if (filesList == null) {
        completer.complete(const []);
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
        final baseKey = p.basenameWithoutExtension(name).toLowerCase();
        final lrcFile = lrcFileMap[baseKey];
        if (lrcFile != null) {
          final lrcBufPromise = lrcFile.callMethod<JSPromise>('arrayBuffer'.toJS);
          final lrcBuf = (await lrcBufPromise.toDart) as JSArrayBuffer;
          companionLyrics = LrcParser.parseBytes(lrcBuf.toDart.asUint8List());
        }

        final blobUrl = urlObj.callMethod<JSString>('createObjectURL'.toJS, file).toDart;

        final track = AudioMetadataParser.parseBytes(
          id: blobUrl,
          filePath: blobUrl,
          fileName: name,
          folderPath: folderName,
          fileSize: size,
          headerBytes: headerBytes,
          companionLyrics: companionLyrics,
          indexSeed: i,
        );
        parsedTracks.add(track);
      }

      completer.complete(parsedTracks);
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
