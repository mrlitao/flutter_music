import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import '../models/track.dart';
import '../services/audio_engine_service.dart';
import '../widgets/dialogs_and_sheets.dart';
import '../widgets/fluid_wave_visualizer.dart';
import '../widgets/glass_widgets.dart';
import '../widgets/synchronized_lyrics_panel.dart';

enum LibraryCategory {
  allTracks('本地歌曲', Icons.music_note_rounded),
  favorites('我喜欢的', Icons.favorite_rounded),
  albums('专辑视图', Icons.album_rounded),
  artists('艺术家', Icons.mic_external_on_rounded),
  folders('文件夹', Icons.folder_rounded);

  const LibraryCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Bottom navigation tabs for Small Window / Mobile layout.
/// Note: The raised circular player button sits in the center above the row and toggles the Player view.
enum MobileNavTab {
  home('首页', Icons.home_rounded),
  localSongs('本地歌曲', Icons.queue_music_rounded),
  library('资料库', Icons.library_music_rounded),
  profile('我的', Icons.person_outline_rounded);

  const MobileNavTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Adaptive Multi-Platform Main Screen for Windows, Web, iOS, Android, and HarmonyOS NEXT.
class AuraMusicHomeScreen extends StatefulWidget {
  const AuraMusicHomeScreen({super.key, required this.controller});

  final AudioEngineController controller;

  @override
  State<AuraMusicHomeScreen> createState() => _AuraMusicHomeScreenState();
}

class _AuraMusicHomeScreenState extends State<AuraMusicHomeScreen>
    with SingleTickerProviderStateMixin {
  LibraryCategory _selectedCategory = LibraryCategory.allTracks;

  /// Active regular tab in small-window (mobile) mode.
  MobileNavTab _mobileActiveTab = MobileNavTab.localSongs;

  /// Whether the full Fluid Wave Ripple + Lyrics Player Main Page is open in small-window mode.
  bool _isMobilePlayerOpen = false;

  /// Drives the circular wave-ripple expansion/contraction transition between the clicked
  /// circular player button and the full Player Main View.
  late final AnimationController _rippleTransitionController;

  /// Stores the local tap offset within the main stage stack (defaults to bottom-center circular icon).
  Offset? _rippleOriginInStack;
  final GlobalKey _mobileStageStackKey = GlobalKey();
  final GlobalKey _circularPlayerBtnKey = GlobalKey();

  bool _mobileShowLyricsFull = false;
  String? _activeAnchorLetter;
  final ScrollController _trackListScrollController = ScrollController();
  final FocusNode _keyboardFocusNode = FocusNode();
  final TextEditingController _searchTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rippleTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
      reverseDuration: const Duration(milliseconds: 480),
    );
  }

  @override
  void dispose() {
    _rippleTransitionController.dispose();
    _trackListScrollController.dispose();
    _keyboardFocusNode.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (FocusManager.instance.primaryFocus != _keyboardFocusNode &&
        FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    final ctrl = widget.controller;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      ctrl.togglePlayPause();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      ctrl.seekTo(ctrl.position + const Duration(seconds: 5));
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      ctrl.seekTo(ctrl.position - const Duration(seconds: 5));
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      ctrl.setVolume(ctrl.volume + 0.05);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      ctrl.setVolume(ctrl.volume - 0.05);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openImportSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ImportLocalMusicSheet(controller: widget.controller),
    );
  }

  void _openEqAndWaveSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EqualizerAndWaveSheet(controller: widget.controller),
    );
  }

  void _openPlayingQueueSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PlayingQueueSheet(controller: widget.controller),
    );
  }

  void _selectCategory(LibraryCategory cat) {
    setState(() {
      _selectedCategory = cat;
      if (cat == LibraryCategory.allTracks) {
        widget.controller.setFilters(clearAll: true);
      } else if (cat == LibraryCategory.favorites) {
        widget.controller.setFilters(clearAll: true);
        widget.controller.setFilters(onlyFavorites: true);
      }
    });
  }

  /// Computes the exact center of the raised circular player button in the stage Stack's coordinate space.
  void _captureRippleOriginFromCircularButton([Offset? globalTapPosition]) {
    try {
      final stackBox = _mobileStageStackKey.currentContext?.findRenderObject() as RenderBox?;
      if (stackBox != null) {
        if (globalTapPosition != null) {
          _rippleOriginInStack = stackBox.globalToLocal(globalTapPosition);
          return;
        }
        final btnBox = _circularPlayerBtnKey.currentContext?.findRenderObject() as RenderBox?;
        if (btnBox != null) {
          final btnCenterGlobal = btnBox.localToGlobal(btnBox.size.center(Offset.zero));
          _rippleOriginInStack = stackBox.globalToLocal(btnCenterGlobal);
          return;
        }
      }
    } catch (_) {}
    _rippleOriginInStack = null;
  }

  /// Toggles the full Player view with a circular wave-ripple expansion/contraction animation
  /// radiating from the clicked circular player icon to the full screen (and back on exit).
  void _toggleMobilePlayerOverlay([Offset? globalTapPosition]) {
    _captureRippleOriginFromCircularButton(globalTapPosition);
    setState(() {
      _isMobilePlayerOpen = !_isMobilePlayerOpen;
      if (_isMobilePlayerOpen) {
        _rippleTransitionController.forward();
      } else {
        _rippleTransitionController.reverse();
      }
    });
  }

  void _selectMobileTab(MobileNavTab tab) {
    _captureRippleOriginFromCircularButton();
    setState(() {
      _mobileActiveTab = tab;
      if (_isMobilePlayerOpen) {
        _isMobilePlayerOpen = false;
        _rippleTransitionController.reverse();
      }
      if (tab == MobileNavTab.localSongs) {
        widget.controller.setFilters(clearAll: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final isLight = ctrl.isLightGlassMode;

        return Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: ValueListenableBuilder<SpectrumFrame>(
              valueListenable: ctrl.spectrumNotifier,
              builder: (context, liveSpectrum, staticBody) {
                return DynamicAuroraBackground(
                  colors: ctrl.activeAuroraColors,
                  phase: liveSpectrum.phase,
                  bassEnergy: liveSpectrum.bassEnergy,
                  isLightMode: isLight,
                  child: staticBody!,
                );
              },
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isDesktopWide = constraints.maxWidth >= 860;
                    if (isDesktopWide) {
                      return _buildDesktopWorkspace(context, ctrl, constraints);
                    }
                    return _buildMobileLayout(context, ctrl, constraints);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // SMALL WINDOW / MOBILE LAYOUT (iOS / Android / HarmonyOS Phone / Small Window)
  // ===========================================================================
  Widget _buildMobileLayout(
    BuildContext context,
    AudioEngineController ctrl,
    BoxConstraints constraints,
  ) {
    final isLight = ctrl.isLightGlassMode;
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white60;
    final accent = ctrl.activeAuroraColors.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          // 1. Main Page Body with Click-Point-to-Fullscreen Wave Ripple Expansion/Contraction Transition
          Expanded(
            child: LayoutBuilder(
              builder: (context, stageConstraints) {
                final defaultOrigin = Offset(
                  stageConstraints.maxWidth / 2,
                  stageConstraints.maxHeight + 28,
                );
                final effectiveOrigin = _rippleOriginInStack ?? defaultOrigin;

                return Stack(
                  key: _mobileStageStackKey,
                  fit: StackFit.expand,
                  children: [
                    // Base Layer: Active Tab Page (首页 / 本地歌曲 / 资料库 / 我的)
                    _buildMobileTabBody(ctrl, textColor, subColor, accent),

                    // Ripple Reveal Layer: Player Main View expanding/contracting from click point
                    AnimatedBuilder(
                      animation: _rippleTransitionController,
                      builder: (context, child) {
                        final double rawVal = _rippleTransitionController.value;
                        if (rawVal <= 0.001 && !_isMobilePlayerOpen) {
                          return const SizedBox.shrink();
                        }

                        final double curvedProgress = CurvedAnimation(
                          parent: _rippleTransitionController,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInOutCubic,
                        ).value;

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            // Wavy circular reveal clip of the Player Main View
                            ClipPath(
                              clipper: _WaveRippleRevealClipper(
                                origin: effectiveOrigin,
                                progress: curvedProgress,
                                minRadius: 28.0,
                              ),
                              child: child,
                            ),

                            // Concentric glowing wave ripple rings radiating between click point and fullscreen
                            if (rawVal > 0.01 && rawVal < 0.99)
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _TransitionWaveRingsPainter(
                                    origin: effectiveOrigin,
                                    progress: curvedProgress,
                                    colors: ctrl.activeAuroraColors,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                      child: _buildMobilePlayerMainView(ctrl, textColor, subColor, accent),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          // 2. Bottom TabBar with Raised Circular Player Icon (Not on the same horizontal line!)
          _buildMobileBottomTabBarWithRaisedPlayer(ctrl, textColor, subColor, accent, isLight),
        ],
      ),
    );
  }

  /// Renders the active page among [首页, 本地歌曲, 资料库, 我的].
  Widget _buildMobileTabBody(
    AudioEngineController ctrl,
    Color textColor,
    Color subColor,
    Color accent,
  ) {
    switch (_mobileActiveTab) {
      case MobileNavTab.home:
        return _buildMobileBlankPage(
          key: const ValueKey('tab_home'),
          isLight: ctrl.isLightGlassMode,
        );
      case MobileNavTab.localSongs:
        return _buildMobileLocalSongsPage(
          ctrl: ctrl,
          textColor: textColor,
          subColor: subColor,
          accent: accent,
        );
      case MobileNavTab.library:
        return _buildMobileBlankPage(
          key: const ValueKey('tab_library'),
          isLight: ctrl.isLightGlassMode,
        );
      case MobileNavTab.profile:
        return _buildMobileBlankPage(
          key: const ValueKey('tab_profile'),
          isLight: ctrl.isLightGlassMode,
        );
    }
  }

  /// Clean frosted glass blank placeholder for 首页 / 资料库 / 我的 as requested ("先留空").
  Widget _buildMobileBlankPage({required Key key, required bool isLight}) {
    return AuraGlassContainer(
      key: key,
      borderRadius: 24,
      isLightMode: isLight,
      width: double.infinity,
      height: double.infinity,
      child: const SizedBox.expand(),
    );
  }

  /// 本地歌曲页：展示已导入的所有歌曲，顶部组合式「搜索框 + 8种排序图标」。
  Widget _buildMobileLocalSongsPage({
    required AudioEngineController ctrl,
    required Color textColor,
    required Color subColor,
    required Color accent,
  }) {
    final isLight = ctrl.isLightGlassMode;
    return AuraGlassContainer(
      key: const ValueKey('tab_local_songs'),
      borderRadius: 24,
      isLightMode: isLight,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Title Row + Import Local Music Quick Button
          Row(
            children: [
              Icon(Icons.queue_music_rounded, color: accent, size: 22),
              const SizedBox(width: 8),
              Text(
                '本地歌曲',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: accent.withValues(alpha: 0.18),
                ),
                child: Text(
                  '${ctrl.filteredTracks.length} 首',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  backgroundColor: accent.withValues(alpha: 0.14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _openImportSheet,
                icon: Icon(Icons.folder_open_rounded, size: 16, color: accent),
                label: Text(
                  '导入音乐',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Combined Search Input + Sort Icon Widget
          _buildCombinedSearchAndSortBar(
            ctrl: ctrl,
            textColor: textColor,
            subColor: subColor,
            accent: accent,
            isLight: isLight,
          ),
          const SizedBox(height: 10),

          // Active Sort Indicator Pill
          Row(
            children: [
              Icon(ctrl.sortOption.icon, size: 13, color: accent),
              const SizedBox(width: 4),
              Text(
                '当前排序：${ctrl.sortOption.label} (${ctrl.sortOption.subtitle})',
                style: TextStyle(fontSize: 11.5, color: subColor, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Imported Songs List
          Expanded(
            child: _buildTrackListView(ctrl, textColor, subColor, accent),
          ),
        ],
      ),
    );
  }

  /// 组合式「搜索框 + 右侧排序 Icon」组件
  /// 支持：导入时间正倒序、名称正倒序、歌手名称正倒序、播放次数正倒序
  Widget _buildCombinedSearchAndSortBar({
    required AudioEngineController ctrl,
    required Color textColor,
    required Color subColor,
    required Color accent,
    required bool isLight,
  }) {
    final containerBg = isLight
        ? Colors.black.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.09);
    final borderCol = isLight
        ? Colors.black.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.16);

    return Container(
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: containerBg,
        border: Border.all(color: borderCol, width: 1.0),
      ),
      child: Row(
        children: [
          const SizedBox(width: 11),
          Icon(Icons.search_rounded, size: 18, color: subColor),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchTextController,
              onChanged: ctrl.setSearchQuery,
              style: TextStyle(color: textColor, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索本地歌曲、歌手、专辑...',
                hintStyle: TextStyle(color: subColor.withValues(alpha: 0.6), fontSize: 12.5),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (ctrl.searchQuery.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '清除搜索',
              icon: Icon(Icons.clear_rounded, size: 16, color: subColor),
              onPressed: () {
                _searchTextController.clear();
                ctrl.setSearchQuery('');
              },
            ),

          Container(
            width: 1,
            height: 22,
            color: borderCol,
          ),

          PopupMenuButton<TrackSortOption>(
            tooltip: '排序方式 (${ctrl.sortOption.label})',
            initialValue: ctrl.sortOption,
            onSelected: ctrl.setSortOption,
            color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: accent.withValues(alpha: 0.35)),
            ),
            itemBuilder: (context) {
              return TrackSortOption.values.map((option) {
                final isSelected = ctrl.sortOption == option;
                return PopupMenuItem<TrackSortOption>(
                  value: option,
                  child: Row(
                    children: [
                      Icon(
                        option.icon,
                        size: 17,
                        color: isSelected ? accent : subColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              option.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? accent : textColor,
                              ),
                            ),
                            Text(
                              option.subtitle,
                              style: TextStyle(fontSize: 10.5, color: subColor),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_rounded, size: 17, color: accent),
                    ],
                  ),
                );
              }).toList();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert_rounded, size: 19, color: accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 播放主界面（点击底部凸起圆形播放器图标后以波纹扩散动画进入，再点击以波纹收起动画返回上一页）
  Widget _buildMobilePlayerMainView(
    AudioEngineController ctrl,
    Color textColor,
    Color subColor,
    Color accent,
  ) {
    final isLight = ctrl.isLightGlassMode;
    return AuraGlassContainer(
      key: const ValueKey('mobile_player_main_view'),
      borderRadius: 24,
      isLightMode: isLight,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        children: [
          // Top Bar with Back to Previous Page Button & Lyrics/Visualizer Toggle
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _toggleMobilePlayerOverlay(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withValues(alpha: isLight ? 0.45 : 0.08),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: textColor),
                      const SizedBox(width: 4),
                      Text(
                        '返回${_mobileActiveTab.label}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: accent.withValues(alpha: 0.16),
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      ctrl.currentTrack.formatBadge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: _mobileShowLyricsFull ? '放大流线波纹' : '展开全屏歌词',
                onPressed: () => setState(() => _mobileShowLyricsFull = !_mobileShowLyricsFull),
                icon: Icon(
                  _mobileShowLyricsFull ? Icons.radar_rounded : Icons.lyrics_rounded,
                  size: 19,
                  color: accent,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: '正在播放列表 (${ctrl.playlist.length})',
                onPressed: _openPlayingQueueSheet,
                icon: Icon(Icons.queue_music_rounded, size: 19, color: accent),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: '均衡器与波纹设置',
                onPressed: _openEqAndWaveSheet,
                icon: Icon(Icons.tune_rounded, size: 19, color: subColor),
              ),
            ],
          ),

          // Center Fluid Wave Ripple + Synchronized Lyrics Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final visSize = (box.maxHeight * (_mobileShowLyricsFull ? 0.32 : 0.58))
                    .clamp(130.0, 260.0)
                    .clamp(130.0, box.maxWidth * 0.85);
                return Column(
                  children: [
                    Center(
                      child: ValueListenableBuilder<SpectrumFrame>(
                        valueListenable: ctrl.spectrumNotifier,
                        builder: (context, liveSpectrum, _) {
                          return FluidWaveRippleVisualizer(
                            track: ctrl.currentTrack,
                            spectrum: liveSpectrum,
                            colors: ctrl.activeAuroraColors,
                            isPlaying: ctrl.isPlaying,
                            size: visSize,
                            onTapCenter: ctrl.togglePlayPause,
                          );
                        },
                      ),
                    ),
                    Text(
                      ctrl.currentTrack.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${ctrl.currentTrack.artist} · ${ctrl.currentTrack.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: SynchronizedLyricsPanel(
                        lyrics: ctrl.currentTrack.lyrics,
                        activeIndex: ctrl.activeLyricIndex,
                        accentColor: accent,
                        isLightMode: isLight,
                        onTapLine: ctrl.seekTo,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Compact Playback Transport Controls inside the Player Main View
          _buildCompactPlayerControls(context, ctrl, textColor, subColor, accent, isLight),
        ],
      ),
    );
  }

  Widget _buildCompactPlayerControls(
    BuildContext context,
    AudioEngineController ctrl,
    Color textColor,
    Color subColor,
    Color accent,
    bool isLight,
  ) {
    final totalMs = ctrl.duration.inMilliseconds.clamp(1, 36000000);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<Duration>(
          valueListenable: ctrl.positionNotifier,
          builder: (context, livePos, _) {
            final posMs = livePos.inMilliseconds.clamp(0, totalMs);
            final progress = (posMs / totalMs).clamp(0.0, 1.0);
            return Row(
              children: [
                Text(
                  _formatDuration(livePos),
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: subColor),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    ),
                    child: Slider(
                      value: progress,
                      activeColor: accent,
                      inactiveColor: isLight
                          ? Colors.black.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.16),
                      onChanged: (v) {
                        ctrl.seekTo(Duration(milliseconds: (v * totalMs).round()));
                      },
                    ),
                  ),
                ),
                Text(
                  _formatDuration(ctrl.duration),
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: subColor),
                ),
              ],
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: ctrl.playMode.label,
              visualDensity: VisualDensity.compact,
              onPressed: ctrl.cyclePlayMode,
              icon: Icon(ctrl.playMode.icon, size: 20, color: subColor),
            ),
            IconButton(
              tooltip: '上一首',
              visualDensity: VisualDensity.compact,
              onPressed: ctrl.previousTrack,
              icon: Icon(Icons.skip_previous_rounded, size: 28, color: textColor),
            ),
            GestureDetector(
              onTap: ctrl.togglePlayPause,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      ctrl.activeAuroraColors[0],
                      ctrl.activeAuroraColors[1],
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  ctrl.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            IconButton(
              tooltip: '下一首',
              visualDensity: VisualDensity.compact,
              onPressed: ctrl.nextTrack,
              icon: Icon(Icons.skip_next_rounded, size: 28, color: textColor),
            ),
            IconButton(
              tooltip: ctrl.currentTrack.isFavorite ? '取消喜欢' : '喜欢',
              visualDensity: VisualDensity.compact,
              onPressed: () => ctrl.toggleFavorite(ctrl.currentTrack.id),
              icon: Icon(
                ctrl.currentTrack.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 20,
                color: ctrl.currentTrack.isFavorite ? Colors.pinkAccent : subColor,
              ),
            ),
          ],
        ),
        // Mobile Volume Control Row (Mute/Unmute + Slider)
        Row(
          children: [
            IconButton(
              tooltip: ctrl.volume <= 0.01 ? '取消静音' : '静音',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: ctrl.toggleMute,
              icon: Icon(
                ctrl.volume <= 0.01 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 18,
                color: ctrl.volume <= 0.01 ? Colors.pinkAccent : subColor,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
                ),
                child: Slider(
                  value: ctrl.volume,
                  activeColor: accent,
                  inactiveColor: isLight
                      ? Colors.black.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.16),
                  onChanged: ctrl.setVolume,
                ),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(ctrl.volume * 100).round()}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: subColor),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 小窗口底部 TabBar：
  /// 4 个常规按钮（首页、本地歌曲 | 资料库、我的）位于底部毛玻璃栏同一水平行；
  /// 中间「圆形图标展示播放器」向上悬浮凸起（不与其他 tabbar 按钮同一行），
  /// 点击触发从点击点到全屏播放页的波纹扩散/收起动画。
  Widget _buildMobileBottomTabBarWithRaisedPlayer(
    AudioEngineController ctrl,
    Color textColor,
    Color subColor,
    Color accent,
    bool isLight,
  ) {
    final totalMs = ctrl.duration.inMilliseconds.clamp(1, 36000000);

    return SizedBox(
      height: 82,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Bottom horizontal frosted glass tab bar housing the 4 regular tabs
          AuraGlassContainer(
            height: 58,
            borderRadius: 22,
            blurSigma: 26,
            isLightMode: isLight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: _buildMobileTabItem(
                    tab: MobileNavTab.home,
                    isSelected: !_isMobilePlayerOpen && _mobileActiveTab == MobileNavTab.home,
                    accent: accent,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _selectMobileTab(MobileNavTab.home),
                  ),
                ),
                Expanded(
                  child: _buildMobileTabItem(
                    tab: MobileNavTab.localSongs,
                    isSelected:
                        !_isMobilePlayerOpen && _mobileActiveTab == MobileNavTab.localSongs,
                    accent: accent,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _selectMobileTab(MobileNavTab.localSongs),
                  ),
                ),

                // Center Gap reserved for the raised circular player icon
                const SizedBox(width: 74),

                Expanded(
                  child: _buildMobileTabItem(
                    tab: MobileNavTab.library,
                    isSelected: !_isMobilePlayerOpen && _mobileActiveTab == MobileNavTab.library,
                    accent: accent,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _selectMobileTab(MobileNavTab.library),
                  ),
                ),
                Expanded(
                  child: _buildMobileTabItem(
                    tab: MobileNavTab.profile,
                    isSelected: !_isMobilePlayerOpen && _mobileActiveTab == MobileNavTab.profile,
                    accent: accent,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _selectMobileTab(MobileNavTab.profile),
                  ),
                ),
              ],
            ),
          ),

          // Center Raised Circular Player Button (Elevated above the TabBar row!)
          Positioned(
            top: 0,
            child: GestureDetector(
              key: const ValueKey('raised_circular_player_tab_button'),
              onTapUp: (details) => _toggleMobilePlayerOverlay(details.globalPosition),
              child: ValueListenableBuilder<SpectrumFrame>(
                valueListenable: ctrl.spectrumNotifier,
                builder: (context, liveSpectrum, _) {
                  final posMs = ctrl.positionNotifier.value.inMilliseconds.clamp(0, totalMs);
                  final progress = (posMs / totalMs).clamp(0.0, 1.0);
                  return Container(
                    key: _circularPlayerBtnKey,
                    width: 64,
                    height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            ctrl.activeAuroraColors[0],
                            ctrl.activeAuroraColors[1],
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: _isMobilePlayerOpen ? 0.65 : 0.45),
                            blurRadius: _isMobilePlayerOpen ? 20 : 14,
                            spreadRadius: _isMobilePlayerOpen ? 2 : 1,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: _isMobilePlayerOpen ? 0.9 : 0.55),
                          width: 2.2,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 58,
                            height: 58,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 2.2,
                              backgroundColor: Colors.white.withValues(alpha: 0.18),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          Transform.rotate(
                            angle: liveSpectrum.phase * 0.16,
                            child: AlbumCoverAvatar(
                              coverBytes: ctrl.currentTrack.coverBytes,
                              colors: ctrl.activeAuroraColors,
                              size: 48,
                              isCircular: true,
                            ),
                          ),
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.52),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              _isMobilePlayerOpen
                                  ? Icons.keyboard_arrow_down_rounded
                                  : (ctrl.isPlaying
                                        ? Icons.graphic_eq_rounded
                                        : Icons.play_arrow_rounded),
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabItem({
    required MobileNavTab tab,
    required bool isSelected,
    required Color accent,
    required Color textColor,
    required Color subColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tab.icon,
              size: 21,
              color: isSelected ? accent : subColor,
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? textColor : subColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DESKTOP / TABLET WIDESCREEN WORKSPACE (Windows / iPad / HarmonyOS Tablet)
  // ===========================================================================
  Widget _buildDesktopWorkspace(
    BuildContext context,
    AudioEngineController ctrl,
    BoxConstraints constraints,
  ) {
    final isLight = ctrl.isLightGlassMode;
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white60;
    final accent = ctrl.activeAuroraColors.first;
    final bool isMediumDesktop = constraints.maxWidth <= 930;
    final double sidebarWidth = isMediumDesktop ? 186.0 : 215.0;
    final double libraryWidth =
        isMediumDesktop ? 252.0 : (constraints.maxWidth * 0.29).clamp(280.0, 360.0);

    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // 1. Left Frosted Sidebar
                AuraGlassContainer(
                  width: sidebarWidth,
                  borderRadius: 22,
                  isLightMode: isLight,
                  padding: EdgeInsets.all(isMediumDesktop ? 12 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  ctrl.activeAuroraColors[0],
                                  ctrl.activeAuroraColors[1],
                                ],
                              ),
                            ),
                            child: const Icon(Icons.waves_rounded, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AuraMusic',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: textColor,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                Text(
                                  '本地音乐播放器',
                                  style: TextStyle(fontSize: 10.5, color: subColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      Text(
                        '本机音乐库',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: subColor,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),

                      for (final cat in LibraryCategory.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _buildSidebarNavTile(
                            category: cat,
                            isSelected: _selectedCategory == cat,
                            count: _getCategoryCount(ctrl, cat),
                            accent: accent,
                            textColor: textColor,
                            subColor: subColor,
                            isLight: isLight,
                            onTap: () => _selectCategory(cat),
                          ),
                        ),

                      const Spacer(),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent.withValues(alpha: 0.22),
                            foregroundColor: textColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: accent.withValues(alpha: 0.5)),
                            ),
                          ),
                          onPressed: _openImportSheet,
                          icon: Icon(Icons.create_new_folder_rounded, size: 17, color: accent),
                          label: const Text(
                            '扫描 / 导入本机音乐',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: isLight
                              ? Colors.black.withValues(alpha: 0.04)
                              : Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: isLight
                                ? Colors.black.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    ctrl.currentTrack.formatBadge,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${(ctrl.currentTrack.sampleRateHz / 1000).toStringAsFixed(1)}kHz · 实时 FFT 波纹引擎',
                              style: TextStyle(fontSize: 10.5, color: subColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // 2. Center Library List / Grid Panel
                SizedBox(
                  width: libraryWidth,
                  child: AuraGlassContainer(
                    borderRadius: 22,
                    isLightMode: isLight,
                    padding: const EdgeInsets.all(14),
                    child: _buildLibraryContent(ctrl, textColor, subColor, accent),
                  ),
                ),

                const SizedBox(width: 12),

                // 3. Right Immersive Fluid Streamline Wave Ripple & Lyrics Stage (Vertical 上下布局)
                Expanded(
                  child: AuraGlassContainer(
                    borderRadius: 22,
                    isLightMode: isLight,
                    padding: EdgeInsets.fromLTRB(
                      isMediumDesktop ? 14 : 20,
                      14,
                      isMediumDesktop ? 14 : 20,
                      12,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        color: accent.withValues(alpha: 0.16),
                                        border: Border.all(color: accent.withValues(alpha: 0.45)),
                                      ),
                                      child: Text(
                                        'HI-RES AUDIO · ${ctrl.currentTrack.formatBadge}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (ctrl.sleepRemaining != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        color: Colors.amber.withValues(alpha: 0.2),
                                      ),
                                      child: Text(
                                        '🌙 ${ctrl.sleepRemaining!.inMinutes}:${(ctrl.sleepRemaining!.inSeconds % 60).toString().padLeft(2, "0")}',
                                        style: const TextStyle(fontSize: 11, color: Colors.amber),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    backgroundColor: accent.withValues(alpha: 0.14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _openPlayingQueueSheet,
                                  icon: Icon(Icons.queue_music_rounded, size: 16, color: accent),
                                  label: Text(
                                    '播放列表 (${ctrl.playlist.length})',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '切换深色极光 / 浅色磨砂玻璃',
                                  onPressed: ctrl.toggleGlassBrightnessMode,
                                  icon: Icon(
                                    isLight ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                    size: 19,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Vertical 上下布局: Top = FluidWaveRippleVisualizer, Bottom = Title + Lyrics
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, stageBox) {
                              final double maxVisHeight = stageBox.maxHeight * 0.50;
                              final double maxVisWidth = stageBox.maxWidth * 0.88;
                              final double visSize = math
                                  .min(maxVisHeight, maxVisWidth)
                                  .clamp(140.0, 290.0);
                              return Column(
                                children: [
                                  const SizedBox(height: 4),
                                  Center(
                                    child: ValueListenableBuilder<SpectrumFrame>(
                                      valueListenable: ctrl.spectrumNotifier,
                                      builder: (context, liveSpectrum, _) {
                                        return FluidWaveRippleVisualizer(
                                          track: ctrl.currentTrack,
                                          spectrum: liveSpectrum,
                                          colors: ctrl.activeAuroraColors,
                                          isPlaying: ctrl.isPlaying,
                                          size: visSize,
                                          onTapCenter: ctrl.togglePlayPause,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    ctrl.currentTrack.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isMediumDesktop ? 17 : 20,
                                      fontWeight: FontWeight.w800,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${ctrl.currentTrack.artist} · ${ctrl.currentTrack.album}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12.5, color: subColor),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: SynchronizedLyricsPanel(
                                      lyrics: ctrl.currentTrack.lyrics,
                                      activeIndex: ctrl.activeLyricIndex,
                                      accentColor: accent,
                                      isLightMode: isLight,
                                      onTapLine: ctrl.seekTo,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        _buildMiniSpectrumStrip(ctrl, accent),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildBottomPlaybackBar(context, ctrl, isDesktop: true),
        ],
      ),
    );
  }

  // ===========================================================================
  // SHARED LIBRARY LIST / ALBUMS / ARTISTS / FOLDERS CONTENT
  // ===========================================================================
  Widget _buildLibraryContent(
    AudioEngineController ctrl,
    Color textColor,
    Color subColor,
    Color accent,
  ) {
    final isLight = ctrl.isLightGlassMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCombinedSearchAndSortBar(
          ctrl: ctrl,
          textColor: textColor,
          subColor: subColor,
          accent: accent,
          isLight: isLight,
        ),
        const SizedBox(height: 8),

        if (ctrl.selectedAlbumFilter != null ||
            ctrl.selectedArtistFilter != null ||
            ctrl.selectedFolderFilter != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '筛选: ${ctrl.selectedAlbumFilter ?? ctrl.selectedArtistFilter ?? p.basename(ctrl.selectedFolderFilter!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => ctrl.setFilters(clearAll: true),
                  icon: Icon(Icons.arrow_back_rounded, size: 14, color: accent),
                  label: Text('返回全部', style: TextStyle(fontSize: 11.5, color: accent)),
                ),
              ],
            ),
          ),

        Expanded(
          child: _buildCategoryBody(ctrl, textColor, subColor, accent),
        ),
      ],
    );
  }

  Widget _buildCategoryBody(
    AudioEngineController ctrl,
    Color textColor,
    Color subColor,
    Color accent,
  ) {
    if (_selectedCategory == LibraryCategory.albums && ctrl.selectedAlbumFilter == null) {
      final albums = ctrl.albumsMap.entries.toList();
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 165,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.84,
        ),
        itemCount: albums.length,
        itemBuilder: (context, idx) {
          final entry = albums[idx];
          final firstTrack = entry.value.first;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => ctrl.setFilters(album: entry.key),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withValues(alpha: ctrl.isLightGlassMode ? 0.35 : 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: AlbumCoverAvatar(
                        coverBytes: firstTrack.coverBytes,
                        colors: firstTrack.paletteColors,
                        size: 92,
                        borderRadius: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textColor),
                  ),
                  Text(
                    '${entry.value.length} 首歌曲 · ${firstTrack.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (_selectedCategory == LibraryCategory.artists && ctrl.selectedArtistFilter == null) {
      final artists = ctrl.artistsMap.entries.toList();
      return ListView.separated(
        itemCount: artists.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, idx) {
          final entry = artists[idx];
          final firstTrack = entry.value.first;
          return ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Colors.white.withValues(alpha: ctrl.isLightGlassMode ? 0.35 : 0.05),
            leading: AlbumCoverAvatar(
              coverBytes: firstTrack.coverBytes,
              colors: firstTrack.paletteColors,
              size: 40,
              isCircular: true,
            ),
            title: Text(
              entry.key,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
            ),
            subtitle: Text(
              '共 ${entry.value.length} 首本机曲目',
              style: TextStyle(fontSize: 11, color: subColor),
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: subColor, size: 18),
            onTap: () => ctrl.setFilters(artist: entry.key),
          );
        },
      );
    }

    if (_selectedCategory == LibraryCategory.folders && ctrl.selectedFolderFilter == null) {
      final folders = ctrl.foldersMap.entries.toList();
      return ListView.separated(
        itemCount: folders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, idx) {
          final entry = folders[idx];
          return ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Colors.white.withValues(alpha: ctrl.isLightGlassMode ? 0.35 : 0.05),
            leading: Icon(Icons.folder_special_rounded, color: accent, size: 28),
            title: Text(
              p.basename(entry.key).isEmpty ? entry.key : p.basename(entry.key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
            ),
            subtitle: Text(
              '${entry.value.length} 首 · ${entry.key}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: subColor),
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: subColor, size: 18),
            onTap: () => ctrl.setFilters(folder: entry.key),
          );
        },
      );
    }

    return _buildTrackListView(ctrl, textColor, subColor, accent);
  }

  void _scrollToTrackLetter(String letter, List<Track> tracks) {
    if (tracks.isEmpty || !_trackListScrollController.hasClients) return;
    setState(() => _activeAnchorLetter = letter);

    int targetIdx = -1;
    if (letter == '#') {
      targetIdx = tracks.indexWhere((t) {
        final trimmed = t.title.trim();
        if (trimmed.isEmpty) return false;
        final code = trimmed.toUpperCase().codeUnitAt(0);
        return code < 65 || code > 90;
      });
    } else {
      targetIdx = tracks.indexWhere(
        (t) => t.title.trim().toUpperCase().startsWith(letter),
      );
      if (targetIdx < 0) {
        // Fallback: find first track whose leading ASCII letter is >= target letter
        final targetCode = letter.codeUnitAt(0);
        targetIdx = tracks.indexWhere((t) {
          final trimmed = t.title.trim().toUpperCase();
          if (trimmed.isEmpty) return false;
          final c = trimmed.codeUnitAt(0);
          return c >= targetCode && c <= 90;
        });
      }
    }

    if (targetIdx >= 0) {
      const double itemExtent = 68.0;
      final double maxScroll = _trackListScrollController.position.maxScrollExtent;
      final double targetOffset = (targetIdx * itemExtent).clamp(0.0, maxScroll);
      _trackListScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildTrackListView(
    AudioEngineController ctrl,
    Color textColor,
    Color subColor,
    Color accent,
  ) {
    final tracks = ctrl.filteredTracks;
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded, size: 38, color: subColor),
            const SizedBox(height: 8),
            Text('没有找到匹配的曲目', style: TextStyle(color: subColor, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _openImportSheet,
              icon: Icon(Icons.add_circle_outline_rounded, size: 16, color: accent),
              label: Text('导入本机音乐目录', style: TextStyle(color: accent, fontSize: 12.5)),
            ),
          ],
        ),
      );
    }

    const List<String> alphabet = [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
      'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#',
    ];

    return Stack(
      children: [
        ListView.builder(
          controller: _trackListScrollController,
          itemExtent: 68.0,
          padding: const EdgeInsets.only(right: 26),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            final isCurrent = track.id == ctrl.currentTrack.id;
            final inPlaylist = ctrl.isInPlaylist(track.id);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ctrl.selectTrack(track, autoPlay: true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: isCurrent
                        ? accent.withValues(alpha: ctrl.isLightGlassMode ? 0.18 : 0.20)
                        : Colors.white.withValues(alpha: ctrl.isLightGlassMode ? 0.32 : 0.04),
                    border: Border.all(
                      color: isCurrent
                          ? accent.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      AlbumCoverAvatar(
                        coverBytes: track.coverBytes,
                        colors: track.paletteColors,
                        size: 42,
                        borderRadius: 10,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isCurrent)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 5),
                                    child: Icon(
                                      ctrl.isPlaying
                                          ? Icons.graphic_eq_rounded
                                          : Icons.pause_circle_filled_rounded,
                                      size: 15,
                                      color: accent,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                                      color: isCurrent ? accent : textColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${track.artist} · 播放 ${track.playCount} 次 · ${track.formatBadge}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: subColor),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: inPlaylist ? '从播放列表中移除' : '添加至播放列表',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        onPressed: () => ctrl.toggleInPlaylist(track),
                        icon: Icon(
                          inPlaylist
                              ? Icons.playlist_add_check_rounded
                              : Icons.playlist_add_rounded,
                          size: 19,
                          color: inPlaylist ? accent : subColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        track.formattedDuration,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // Floating A-Z Name Anchor Index Bar on the right
        Positioned(
          right: 0,
          top: 4,
          bottom: 4,
          child: Container(
            key: const ValueKey('az_anchor_bar'),
            width: 22,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: ctrl.isLightGlassMode
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.black.withValues(alpha: 0.35),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 0.8,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, barBox) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: alphabet.map((letter) {
                    final isActive = _activeAnchorLetter == letter;
                    return Expanded(
                      child: InkWell(
                        onTap: () => _scrollToTrackLetter(letter, tracks),
                        child: Center(
                          child: Text(
                            letter,
                            style: TextStyle(
                              fontSize: isActive ? 10.5 : 9.0,
                              height: 1.0,
                              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                              color: isActive ? accent : subColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // BOTTOM FROSTED GLASS MASTER PLAYBACK CONTROL BAR (DESKTOP)
  // ===========================================================================
  Widget _buildBottomPlaybackBar(
    BuildContext context,
    AudioEngineController ctrl, {
    required bool isDesktop,
  }) {
    final isLight = ctrl.isLightGlassMode;
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white60;
    final accent = ctrl.activeAuroraColors.first;

    final totalMs = ctrl.duration.inMilliseconds.clamp(1, 36000000);

    return AuraGlassContainer(
      borderRadius: 22,
      blurSigma: 26,
      isLightMode: isLight,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 18 : 12,
        vertical: isDesktop ? 10 : 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: ctrl.positionNotifier,
            builder: (context, livePos, _) {
              final posMs = livePos.inMilliseconds.clamp(0, totalMs);
              final progress = (posMs / totalMs).clamp(0.0, 1.0);
              return Row(
                children: [
                  Text(
                    _formatDuration(livePos),
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: subColor),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
                      ),
                      child: Slider(
                        value: progress,
                        activeColor: accent,
                        inactiveColor: isLight
                            ? Colors.black.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.16),
                        onChanged: (v) {
                          ctrl.seekTo(Duration(milliseconds: (v * totalMs).round()));
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(ctrl.duration),
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: subColor),
                  ),
                ],
              );
            },
          ),
          Row(
            children: [
              Expanded(
                flex: isDesktop ? 3 : 4,
                child: Row(
                  children: [
                    AlbumCoverAvatar(
                      coverBytes: ctrl.currentTrack.coverBytes,
                      colors: ctrl.activeAuroraColors,
                      size: 38,
                      borderRadius: 10,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ctrl.currentTrack.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                          Text(
                            ctrl.currentTrack.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: subColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: ctrl.currentTrack.isFavorite ? '取消喜欢' : '加入我喜欢的',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ctrl.toggleFavorite(ctrl.currentTrack.id),
                    icon: Icon(
                      ctrl.currentTrack.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 19,
                      color: ctrl.currentTrack.isFavorite ? Colors.pinkAccent : subColor,
                    ),
                  ),
                  IconButton(
                    tooltip: ctrl.playMode.label,
                    visualDensity: VisualDensity.compact,
                    onPressed: ctrl.cyclePlayMode,
                    icon: Icon(ctrl.playMode.icon, size: 19, color: subColor),
                  ),
                  IconButton(
                    tooltip: '上一首',
                    visualDensity: VisualDensity.compact,
                    onPressed: ctrl.previousTrack,
                    icon: Icon(Icons.skip_previous_rounded, size: 25, color: textColor),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: ctrl.togglePlayPause,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            ctrl.activeAuroraColors[0],
                            ctrl.activeAuroraColors[1],
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        ctrl.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '下一首',
                    visualDensity: VisualDensity.compact,
                    onPressed: ctrl.nextTrack,
                    icon: Icon(Icons.skip_next_rounded, size: 25, color: textColor),
                  ),
                  IconButton(
                    tooltip: '均衡器与流线波纹',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openEqAndWaveSheet,
                    icon: Icon(Icons.equalizer_rounded, size: 19, color: accent),
                  ),
                ],
              ),
              if (isDesktop)
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: ctrl.volume <= 0.01 ? '取消静音' : '静音',
                        visualDensity: VisualDensity.compact,
                        onPressed: ctrl.toggleMute,
                        icon: Icon(
                          ctrl.volume <= 0.01
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          size: 19,
                          color: ctrl.volume <= 0.01 ? Colors.pinkAccent : subColor,
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          ),
                          child: Slider(
                            value: ctrl.volume,
                            activeColor: accent,
                            onChanged: ctrl.setVolume,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniSpectrumStrip(AudioEngineController ctrl, Color accent) {
    return ValueListenableBuilder<SpectrumFrame>(
      valueListenable: ctrl.spectrumNotifier,
      builder: (context, liveSpectrum, _) {
        final bins = liveSpectrum.bins;
        return SizedBox(
          height: 22,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(bins.length, (i) {
              final double h = (3.0 + bins[i] * 18.0).clamp(3.0, 21.0);
              return Container(
                width: 3.2,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: Color.lerp(
                    ctrl.activeAuroraColors[0],
                    ctrl.activeAuroraColors[1],
                    i / bins.length,
                  )?.withValues(alpha: 0.75),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildSidebarNavTile({
    required LibraryCategory category,
    required bool isSelected,
    required int count,
    required Color accent,
    required Color textColor,
    required Color subColor,
    required bool isLight,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? accent.withValues(alpha: isLight ? 0.16 : 0.22)
              : Colors.transparent,
          border: isSelected ? Border.all(color: accent.withValues(alpha: 0.45)) : null,
        ),
        child: Row(
          children: [
            Icon(
              category.icon,
              size: 18,
              color: isSelected ? accent : subColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? textColor : subColor,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: isSelected
                    ? accent.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: isLight ? 0.4 : 0.08),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? accent : subColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _getCategoryCount(AudioEngineController ctrl, LibraryCategory cat) {
    switch (cat) {
      case LibraryCategory.allTracks:
        return ctrl.allTracks.length;
      case LibraryCategory.favorites:
        return ctrl.allTracks.where((t) => t.isFavorite).length;
      case LibraryCategory.albums:
        return ctrl.albumsMap.length;
      case LibraryCategory.artists:
        return ctrl.artistsMap.length;
      case LibraryCategory.folders:
        return ctrl.foldersMap.length;
    }
  }

  String _formatDuration(Duration d) {
    final totalSec = d.inSeconds;
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// CustomClipper that expands/contracts a fluid undulating wave-ripple boundary
/// from [origin] (the clicked circular player icon) to the farthest screen corner.
class _WaveRippleRevealClipper extends CustomClipper<Path> {
  const _WaveRippleRevealClipper({
    required this.origin,
    required this.progress,
    required this.minRadius,
  });

  final Offset origin;
  final double progress;
  final double minRadius;

  static double _computeMaxRadius(Size size, Offset origin) {
    final double dx = math.max(origin.dx.abs(), (size.width - origin.dx).abs());
    final double dy = math.max(origin.dy.abs(), (size.height - origin.dy).abs());
    return math.sqrt(dx * dx + dy * dy) + 36.0;
  }

  @override
  Path getClip(Size size) {
    if (progress >= 0.995) {
      return Path()..addRect(Offset.zero & size);
    }

    final double maxRadius = _computeMaxRadius(size, origin);
    final double baseRadius = minRadius + (maxRadius - minRadius) * progress;

    // Fluid sinusoidal wave modulation along the expanding/contracting ripple perimeter
    final double waveAmp = math.sin(progress * math.pi) * 18.0;
    const int steps = 96;
    final Path path = Path();

    for (int i = 0; i <= steps; i++) {
      final double theta = (i / steps) * math.pi * 2.0;
      final double rippleOffset =
          math.sin(theta * 8.0 + progress * math.pi * 6.0) * waveAmp +
          math.cos(theta * 12.0 - progress * math.pi * 4.0) * (waveAmp * 0.45);
      final double r = math.max(0.0, baseRadius + rippleOffset);
      final double x = origin.dx + math.cos(theta) * r;
      final double y = origin.dy + math.sin(theta) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _WaveRippleRevealClipper oldClipper) {
    return oldClipper.progress != progress || oldClipper.origin != origin;
  }
}

/// Renders 3 concentric glowing aurora wave-ripple rings radiating from [origin]
/// along the expanding/contracting transition front.
class _TransitionWaveRingsPainter extends CustomPainter {
  const _TransitionWaveRingsPainter({
    required this.origin,
    required this.progress,
    required this.colors,
  });

  final Offset origin;
  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final double maxRadius = _WaveRippleRevealClipper._computeMaxRadius(size, origin);
    final double baseRadius = 28.0 + (maxRadius - 28.0) * progress;
    final double envelope = math.sin(progress * math.pi).clamp(0.0, 1.0);
    if (envelope <= 0.01) return;

    final Color c1 = colors.isNotEmpty ? colors[0] : const Color(0xFF06B6D4);
    final Color c2 = colors.length > 1 ? colors[1] : const Color(0xFFD946EF);
    final Color c3 = colors.length > 2 ? colors[2] : const Color(0xFF6366F1);

    final ringSpecs = [
      (offset: 0.0, color: c1, width: 3.2, alpha: 0.85 * envelope, lobes: 8),
      (offset: -38.0 * envelope, color: c2, width: 2.2, alpha: 0.65 * envelope, lobes: 10),
      (offset: 32.0 * envelope, color: c3, width: 1.8, alpha: 0.50 * envelope, lobes: 6),
    ];

    const int steps = 96;
    final double waveAmp = envelope * 18.0;

    for (final spec in ringSpecs) {
      final double ringR = baseRadius + spec.offset;
      if (ringR <= 4) continue;

      final Path ringPath = Path();
      for (int i = 0; i <= steps; i++) {
        final double theta = (i / steps) * math.pi * 2.0;
        final double wave =
            math.sin(theta * spec.lobes + progress * math.pi * 6.0) * waveAmp +
            math.cos(theta * 12.0 - progress * math.pi * 4.0) * (waveAmp * 0.45);
        final double r = math.max(1.0, ringR + wave);
        final double x = origin.dx + math.cos(theta) * r;
        final double y = origin.dy + math.sin(theta) * r;
        if (i == 0) {
          ringPath.moveTo(x, y);
        } else {
          ringPath.lineTo(x, y);
        }
      }
      ringPath.close();

      final Paint glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.width * 2.8
        ..color = spec.color.withValues(alpha: (spec.alpha * 0.5).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawPath(ringPath, glowPaint);

      final Paint strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = spec.width
        ..color = spec.color.withValues(alpha: spec.alpha.clamp(0.0, 1.0));
      canvas.drawPath(ringPath, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TransitionWaveRingsPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.origin != origin ||
        oldDelegate.colors != colors;
  }
}
