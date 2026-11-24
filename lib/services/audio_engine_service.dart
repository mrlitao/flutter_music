import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import '../models/track.dart';
import 'demo_wav_generator.dart';
import 'platform_bridge.dart';
import 'spectrum_analyzer.dart';

/// Unified Cross-Platform Audio & Library Controller for Windows, Web (Chrome/Edge),
/// iOS, Android, and HarmonyOS NEXT.
class AudioEngineController extends ChangeNotifier {
  AudioEngineController() {
    _initLibraryAndEngine();
  }

  final PlatformAudioBridge _bridge = PlatformAudioBridge();
  final SpectrumAnalyzer _spectrumAnalyzer = SpectrumAnalyzer();
  Timer? _frameTimer;
  Timer? _positionSyncTimer;
  Timer? _sleepTimer;

  List<Track> _tracks = [];
  final List<String> _scannedFolders = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isScanning = false;
  bool _isDisposed = false;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(seconds: 24);
  double _volume = 0.82;
  double _playbackSpeed = 1.0;
  double _waveIntensity = 0.78;
  PlayMode _playMode = PlayMode.sequence;
  TrackSortOption _sortOption = TrackSortOption.importTimeDesc;
  VisualThemePreset _themePreset = VisualThemePreset.dynamicCover;
  bool _isLightGlassMode = false;
  String _searchQuery = '';
  String? _selectedAlbumFilter;
  String? _selectedArtistFilter;
  String? _selectedFolderFilter;
  bool _onlyFavoritesFilter = false;
  Duration? _sleepRemaining;
  String _statusMessage = '已就绪 · 点击播放键聆听高保真声场，或导入本机音乐';

  List<EqualizerBand> _eqBands = const [
    EqualizerBand(label: '60Hz (低频)', frequencyHz: 60, gainDb: 2.0),
    EqualizerBand(label: '230Hz (中低)', frequencyHz: 230, gainDb: 1.0),
    EqualizerBand(label: '910Hz (人声)', frequencyHz: 910, gainDb: 0.5),
    EqualizerBand(label: '3.6kHz (明亮)', frequencyHz: 3600, gainDb: 1.5),
    EqualizerBand(label: '14kHz (空气感)', frequencyHz: 14000, gainDb: 2.5),
  ];

  SpectrumFrame _currentSpectrum = SpectrumFrame.idle();

  // Getters
  List<Track> get allTracks => _tracks;
  List<String> get scannedFolders => List.unmodifiable(_scannedFolders);
  bool get isPlaying => _isPlaying;
  bool get isScanning => _isScanning;
  Duration get position => _position;
  Duration get duration => _duration.inMilliseconds > 0 ? _duration : currentTrack.duration;
  double get volume => _volume;
  double get playbackSpeed => _playbackSpeed;
  double get waveIntensity => _waveIntensity;
  PlayMode get playMode => _playMode;
  TrackSortOption get sortOption => _sortOption;
  VisualThemePreset get themePreset => _themePreset;
  bool get isLightGlassMode => _isLightGlassMode;
  String get searchQuery => _searchQuery;
  String? get selectedAlbumFilter => _selectedAlbumFilter;
  String? get selectedArtistFilter => _selectedArtistFilter;
  String? get selectedFolderFilter => _selectedFolderFilter;
  bool get onlyFavoritesFilter => _onlyFavoritesFilter;
  Duration? get sleepRemaining => _sleepRemaining;
  String get statusMessage => _statusMessage;
  List<EqualizerBand> get eqBands => _eqBands;
  SpectrumFrame get spectrum => _currentSpectrum;

  Track get currentTrack {
    if (_tracks.isEmpty) {
      return DemoWavGenerator.buildShowcaseTracks().first;
    }
    return _tracks[_currentIndex.clamp(0, _tracks.length - 1)];
  }

  List<Color> get activeAuroraColors {
    if (_themePreset == VisualThemePreset.dynamicCover) {
      return currentTrack.paletteColors;
    }
    return [_themePreset.primary, _themePreset.secondary, _themePreset.tertiary];
  }

  List<Track> get filteredTracks {
    final q = _searchQuery.trim().toLowerCase();
    final matched = _tracks.where((t) {
      if (_onlyFavoritesFilter && !t.isFavorite) return false;
      if (_selectedAlbumFilter != null && t.album != _selectedAlbumFilter) return false;
      if (_selectedArtistFilter != null && t.artist != _selectedArtistFilter) return false;
      if (_selectedFolderFilter != null && t.folderPath != _selectedFolderFilter) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q) ||
          t.formatBadge.toLowerCase().contains(q);
    }).toList();

    matched.sort((a, b) {
      switch (_sortOption) {
        case TrackSortOption.importTimeAsc:
          return a.importedTimestampMs.compareTo(b.importedTimestampMs);
        case TrackSortOption.importTimeDesc:
          return b.importedTimestampMs.compareTo(a.importedTimestampMs);
        case TrackSortOption.titleAsc:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case TrackSortOption.titleDesc:
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case TrackSortOption.artistAsc:
          final cmp = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case TrackSortOption.artistDesc:
          final cmp = b.artist.toLowerCase().compareTo(a.artist.toLowerCase());
          return cmp != 0 ? cmp : b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case TrackSortOption.playCountAsc:
          final cmp = a.playCount.compareTo(b.playCount);
          return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case TrackSortOption.playCountDesc:
          final cmp = b.playCount.compareTo(a.playCount);
          return cmp != 0 ? cmp : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
    });
    return matched;
  }

  Map<String, List<Track>> get albumsMap {
    final map = <String, List<Track>>{};
    for (final t in _tracks) {
      map.putIfAbsent(t.album, () => []).add(t);
    }
    return map;
  }

  Map<String, List<Track>> get artistsMap {
    final map = <String, List<Track>>{};
    for (final t in _tracks) {
      map.putIfAbsent(t.artist, () => []).add(t);
    }
    return map;
  }

  Map<String, List<Track>> get foldersMap {
    final map = <String, List<Track>>{};
    for (final t in _tracks) {
      map.putIfAbsent(t.folderPath, () => []).add(t);
    }
    return map;
  }

  int get activeLyricIndex {
    final lyrics = currentTrack.lyrics;
    if (lyrics.isEmpty) return 0;
    int idx = 0;
    for (int i = 0; i < lyrics.length; i++) {
      if (_position >= lyrics[i].timestamp) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  Future<void> _initLibraryAndEngine() async {
    _tracks = DemoWavGenerator.buildShowcaseTracks();
    _duration = currentTrack.duration;
    await _prepareFftForTrack(currentTrack);
    if (_isDisposed) return;

    // 60 FPS fluid wave ripple spectrum ticker (~16ms)
    _frameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _onFrameTick();
    });

    // Sync actual playback position every 200ms
    _positionSyncTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _syncNativePosition();
    });

    if (!kIsWeb) {
      unawaited(scanDefaultSystemMusicFolders());
    }
  }

  Future<void> _prepareFftForTrack(Track track) async {
    final wavBytes = await _bridge.loadWavBytesForFft(track);
    await _spectrumAnalyzer.prepareForTrack(track, rawWavBytes: wavBytes);
  }

  void _onFrameTick() {
    if (_isPlaying) {
      _position += Duration(milliseconds: (16 * _playbackSpeed).round());
      final totalDur = duration;
      if (_position >= totalDur && totalDur.inMilliseconds > 500) {
        _handleTrackCompleted();
        return;
      }
    }

    final liveWebBins = _bridge.getRealtimeFrequencyBins();

    _currentSpectrum = _spectrumAnalyzer.computeFrame(
      isPlaying: _isPlaying,
      position: _position,
      track: currentTrack,
      eqBands: _eqBands,
      intensity: _waveIntensity,
      webAudioBins: liveWebBins,
    );
    notifyListeners();
  }

  Future<void> _syncNativePosition() async {
    if (!_isPlaying) return;
    try {
      final res = await _bridge.getPositionAndDuration();
      if (res != null) {
        final posMs = res['positionMs'];
        final lenMs = res['durationMs'];
        if (lenMs != null && lenMs > 1000) {
          _duration = Duration(milliseconds: lenMs);
        }
        if (posMs != null && posMs >= 0) {
          if ((posMs - _position.inMilliseconds).abs() > 350) {
            _position = Duration(milliseconds: posMs);
          }
        }
      }
    } catch (_) {}
  }

  void _handleTrackCompleted() {
    if (_playMode == PlayMode.singleLoop) {
      seekTo(Duration.zero);
      play();
    } else {
      nextTrack();
    }
  }

  Future<void> scanDefaultSystemMusicFolders() async {
    if (_isScanning) return;
    _isScanning = true;
    _statusMessage = '正在扫描本机默认音乐目录...';
    notifyListeners();

    int addedCount = 0;
    try {
      final found = await _bridge.scanDefaultDirectories();
      addedCount = _mergeTracks(found);
    } catch (_) {}

    _isScanning = false;
    if (addedCount > 0) {
      _statusMessage = '已自动导入 $addedCount 首本机音乐（共 ${_tracks.length} 首）';
    } else {
      _statusMessage = '内置 4 首高保真声学演示曲目 · 点击「选择文件夹扫描」或「选择音频文件导入」加载本机音乐';
    }
    notifyListeners();
  }

  Future<int> pickAndScanFolder() async {
    if (_isScanning) return 0;
    _isScanning = true;
    _statusMessage = '请选择本机音乐文件夹...';
    notifyListeners();

    int addedCount = 0;
    try {
      final found = await _bridge.pickFolderAndScan();
      addedCount = _mergeTracks(found);
      if (found.isNotEmpty) {
        final firstNewIdx = _tracks.indexWhere((t) => t.id == found.first.id);
        if (firstNewIdx >= 0) {
          await selectTrackAtIndex(firstNewIdx, autoPlay: true);
        }
      }
      _statusMessage = addedCount > 0
          ? '成功从文件夹导入 $addedCount 首本机音乐'
          : '未发现新的音频文件 (.mp3/.flac/.wav/.m4a)';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
    return addedCount;
  }

  Future<int> scanCustomDirectory(String folderPath) async {
    if (_isScanning || folderPath.trim().isEmpty) return 0;
    _isScanning = true;
    _statusMessage = '正在扫描目录: $folderPath ...';
    notifyListeners();

    int addedCount = 0;
    try {
      final found = await _bridge.scanCustomDirectory(folderPath.trim());
      if (!_scannedFolders.contains(folderPath.trim())) {
        _scannedFolders.add(folderPath.trim());
      }
      addedCount = _mergeTracks(found);
      _statusMessage = addedCount > 0
          ? '成功从目录导入 $addedCount 首本机音乐'
          : '未在该目录发现新的支持音频文件';
    } catch (e) {
      _statusMessage = '扫描目录出错: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
    return addedCount;
  }

  Future<int> pickAndImportAudioFiles() async {
    if (_isScanning) return 0;
    _isScanning = true;
    _statusMessage = '请选择本机音频文件 (.mp3 / .flac / .wav / .m4a)...';
    notifyListeners();

    int added = 0;
    try {
      final parsed = await _bridge.pickAudioFiles();
      added = _mergeTracks(parsed);
      if (parsed.isNotEmpty) {
        final firstNewIdx = _tracks.indexWhere((t) => t.id == parsed.first.id);
        if (firstNewIdx >= 0) {
          await selectTrackAtIndex(firstNewIdx, autoPlay: true);
        }
      }
      _statusMessage = added > 0 ? '成功导入 $added 首本机音乐并开始播放' : '未选择新的音频文件';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
    return added;
  }

  int _mergeTracks(List<Track> incoming) {
    final existingIds = _tracks.map((t) => t.id).toSet();
    int added = 0;
    final newTracks = <Track>[];
    for (final track in incoming) {
      if (!existingIds.contains(track.id)) {
        existingIds.add(track.id);
        newTracks.add(track);
        added++;
      }
    }
    if (newTracks.isNotEmpty) {
      _tracks = [...newTracks, ..._tracks];
      _currentIndex = 0;
    }
    return added;
  }

  Future<void> selectTrack(Track track, {bool autoPlay = true}) async {
    final idx = _tracks.indexWhere((t) => t.id == track.id);
    if (idx >= 0) {
      await selectTrackAtIndex(idx, autoPlay: autoPlay);
    }
  }

  Future<void> selectTrackAtIndex(int index, {bool autoPlay = true}) async {
    if (_tracks.isEmpty) return;
    _currentIndex = index.clamp(0, _tracks.length - 1);
    _position = Duration.zero;
    _duration = currentTrack.duration;
    if (autoPlay) {
      final t = _tracks[_currentIndex];
      _tracks[_currentIndex] = t.copyWith(playCount: t.playCount + 1);
    }
    await _prepareFftForTrack(currentTrack);

    if (autoPlay) {
      await play();
    } else {
      await _bridge.stop();
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    final track = currentTrack;
    _isPlaying = true;
    await _prepareFftForTrack(track);

    Uint8List? demoWavBytes;
    if (track.isBuiltInDemo) {
      demoWavBytes = DemoWavGenerator.getOrGenerateWavBytes(track.demoPresetIndex);
    }

    final durMs = await _bridge.play(
      track: track,
      demoWavBytes: demoWavBytes,
      positionMs: _position.inMilliseconds,
      volume: _volume,
      speed: _playbackSpeed,
    );

    if (durMs != null && durMs > 1000) {
      _duration = Duration(milliseconds: durMs);
    }

    _statusMessage = '正在播放: ${track.title} (${track.formatBadge})';
    notifyListeners();
  }

  Future<void> pause() async {
    _isPlaying = false;
    await _bridge.pause();
    _statusMessage = '已暂停: ${currentTrack.title}';
    notifyListeners();
  }

  Future<void> nextTrack() async {
    if (_tracks.isEmpty) return;
    if (_playMode == PlayMode.shuffle && _tracks.length > 1) {
      final rand = math.Random();
      int nextIdx = _currentIndex;
      while (nextIdx == _currentIndex) {
        nextIdx = rand.nextInt(_tracks.length);
      }
      await selectTrackAtIndex(nextIdx, autoPlay: true);
    } else {
      final nextIdx = (_currentIndex + 1) % _tracks.length;
      await selectTrackAtIndex(nextIdx, autoPlay: true);
    }
  }

  Future<void> previousTrack() async {
    if (_tracks.isEmpty) return;
    if (_position.inSeconds > 4) {
      await seekTo(Duration.zero);
      return;
    }
    final prevIdx = (_currentIndex - 1 + _tracks.length) % _tracks.length;
    await selectTrackAtIndex(prevIdx, autoPlay: true);
  }

  Future<void> seekTo(Duration target) async {
    final clampedMs = target.inMilliseconds.clamp(0, duration.inMilliseconds);
    _position = Duration(milliseconds: clampedMs);
    await _bridge.seek(clampedMs);
    notifyListeners();
  }

  Future<void> setVolume(double newVolume) async {
    _volume = newVolume.clamp(0.0, 1.0);
    await _bridge.setVolume(_volume);
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed.clamp(0.5, 2.0);
    _bridge.setSpeed(_playbackSpeed);
    notifyListeners();
  }

  void setWaveIntensity(double intensity) {
    _waveIntensity = intensity.clamp(0.2, 1.4);
    notifyListeners();
  }

  void cyclePlayMode() {
    final modes = PlayMode.values;
    _playMode = modes[(_playMode.index + 1) % modes.length];
    _statusMessage = '播放模式已切换为: ${_playMode.label}';
    notifyListeners();
  }

  void setThemePreset(VisualThemePreset preset) {
    _themePreset = preset;
    notifyListeners();
  }

  void toggleGlassBrightnessMode() {
    _isLightGlassMode = !_isLightGlassMode;
    notifyListeners();
  }

  void toggleFavorite(String trackId) {
    final idx = _tracks.indexWhere((t) => t.id == trackId);
    if (idx >= 0) {
      final current = _tracks[idx];
      _tracks[idx] = current.copyWith(isFavorite: !current.isFavorite);
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSortOption(TrackSortOption option) {
    _sortOption = option;
    _statusMessage = '已按「${option.label}」排序';
    notifyListeners();
  }

  void setFilters({
    String? album,
    String? artist,
    String? folder,
    bool? onlyFavorites,
    bool clearAll = false,
  }) {
    if (clearAll) {
      _selectedAlbumFilter = null;
      _selectedArtistFilter = null;
      _selectedFolderFilter = null;
      _onlyFavoritesFilter = false;
    } else {
      _selectedAlbumFilter = album;
      _selectedArtistFilter = artist;
      _selectedFolderFilter = folder;
      if (onlyFavorites != null) _onlyFavoritesFilter = onlyFavorites;
    }
    notifyListeners();
  }

  void updateEqBand(int index, double gainDb) {
    if (index < 0 || index >= _eqBands.length) return;
    final updated = List<EqualizerBand>.from(_eqBands);
    updated[index] = updated[index].copyWith(gainDb: gainDb.clamp(-12.0, 12.0));
    _eqBands = updated;
    notifyListeners();
  }

  void applyEqPreset(String presetName) {
    switch (presetName) {
      case '重低音 (Bass Boost)':
        _eqBands = [
          _eqBands[0].copyWith(gainDb: 7.5),
          _eqBands[1].copyWith(gainDb: 4.5),
          _eqBands[2].copyWith(gainDb: 0.0),
          _eqBands[3].copyWith(gainDb: 1.5),
          _eqBands[4].copyWith(gainDb: 3.0),
        ];
      case '人声清澈 (Vocal Clear)':
        _eqBands = [
          _eqBands[0].copyWith(gainDb: -1.5),
          _eqBands[1].copyWith(gainDb: 1.0),
          _eqBands[2].copyWith(gainDb: 6.0),
          _eqBands[3].copyWith(gainDb: 4.0),
          _eqBands[4].copyWith(gainDb: 2.0),
        ];
      case '极光流线律动 (Wave Max)':
        _eqBands = [
          _eqBands[0].copyWith(gainDb: 8.0),
          _eqBands[1].copyWith(gainDb: 5.0),
          _eqBands[2].copyWith(gainDb: 4.5),
          _eqBands[3].copyWith(gainDb: 6.0),
          _eqBands[4].copyWith(gainDb: 7.5),
        ];
      default:
        _eqBands = _eqBands.map((b) => b.copyWith(gainDb: 0.0)).toList();
    }
    _statusMessage = '已应用均衡器预设: $presetName';
    notifyListeners();
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepRemaining = duration;
    if (duration != null) {
      _statusMessage = '已开启睡眠定时: ${duration.inMinutes} 分钟后自动暂停';
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_sleepRemaining == null) {
          timer.cancel();
          return;
        }
        final next = _sleepRemaining! - const Duration(seconds: 1);
        if (next.inSeconds <= 0) {
          _sleepRemaining = null;
          timer.cancel();
          pause();
          _statusMessage = '睡眠定时已到，音乐已自动柔和暂停';
        } else {
          _sleepRemaining = next;
        }
        notifyListeners();
      });
    } else {
      _statusMessage = '睡眠定时已关闭';
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _frameTimer?.cancel();
    _positionSyncTimer?.cancel();
    _sleepTimer?.cancel();
    _bridge.dispose();
    super.dispose();
  }
}
