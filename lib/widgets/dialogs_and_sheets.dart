import 'package:material_ui/material_ui.dart';
import '../models/track.dart';
import '../services/audio_engine_service.dart';
import 'glass_widgets.dart';

/// Modal sheet for importing local music folders/files across Windows, iOS, Android, and HarmonyOS.
class ImportLocalMusicSheet extends StatefulWidget {
  const ImportLocalMusicSheet({super.key, required this.controller});

  final AudioEngineController controller;

  @override
  State<ImportLocalMusicSheet> createState() => _ImportLocalMusicSheetState();
}

class _ImportLocalMusicSheetState extends State<ImportLocalMusicSheet> {
  String _importFeedback = '请选择本机音乐文件夹或音频文件进行导入';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final isLight = ctrl.isLightGlassMode;
        final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
        final subColor = isLight ? Colors.black54 : Colors.white70;
        final accent = ctrl.activeAuroraColors.first;

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: AuraGlassContainer(
            borderRadius: 24,
            blurSigma: 28,
            isLightMode: isLight,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.library_music_rounded, color: accent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '导入本机音乐资源',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: subColor, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '支持无损 FLAC、WAV、MP3、MP4、M4A、AAC、OGG、WMA 格式，自动解析内嵌封面与同名 .lrc 歌词',
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
                const SizedBox(height: 16),

                // Import Action Buttons
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildActionButton(
                      icon: Icons.create_new_folder_rounded,
                      label: '选择文件夹扫描',
                      accent: accent,
                      isLight: isLight,
                      onTap: ctrl.isScanning
                          ? null
                          : () async {
                              setState(() => _importFeedback = '正在扫描所选文件夹...');
                              final count = await ctrl.pickAndScanFolder();
                              if (mounted) {
                                setState(() {
                                  _importFeedback = count > 0
                                      ? '已成功导入 $count 首本地音乐'
                                      : '未选择新的音频文件';
                                });
                              }
                            },
                    ),
                    _buildActionButton(
                      icon: Icons.audio_file_rounded,
                      label: '选择音频文件导入',
                      accent: ctrl.activeAuroraColors[1],
                      isLight: isLight,
                      onTap: ctrl.isScanning
                          ? null
                          : () async {
                              setState(() => _importFeedback = '正在解析所选音频文件...');
                              final count = await ctrl.pickAndImportAudioFiles();
                              if (mounted) {
                                setState(() {
                                  _importFeedback = count > 0
                                      ? '已成功导入 $count 首本地音乐'
                                      : '未选择新的音频文件';
                                });
                              }
                            },
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    if (ctrl.isScanning)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        ctrl.isScanning ? '正在处理本机音频资源...' : _importFeedback,
                        style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color accent,
    required bool isLight,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: accent.withValues(alpha: isLight ? 0.14 : 0.18),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isLight ? const Color(0xFF0F172A) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal sheet for 5-band Equalizer, Fluid Wave Ripple Intensity, and Theme/Sleep settings.
class EqualizerAndWaveSheet extends StatelessWidget {
  const EqualizerAndWaveSheet({super.key, required this.controller});

  final AudioEngineController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isLight = controller.isLightGlassMode;
        final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
        final subColor = isLight ? Colors.black54 : Colors.white70;
        final accent = controller.activeAuroraColors.first;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: AuraGlassContainer(
            borderRadius: 24,
            blurSigma: 28,
            isLightMode: isLight,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.equalizer_rounded, color: accent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '声学均衡器 (EQ) & 流线波纹律动调校',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: subColor, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // EQ Presets
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in [
                      '标准原音 (Flat)',
                      '重低音 (Bass Boost)',
                      '人声清澈 (Vocal Clear)',
                      '极光流线律动 (Wave Max)',
                    ])
                      ActionChip(
                        label: Text(preset, style: TextStyle(fontSize: 12, color: textColor)),
                        backgroundColor: isLight
                            ? Colors.black.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.1),
                        side: BorderSide(color: accent.withValues(alpha: 0.35)),
                        onPressed: () => controller.applyEqPreset(preset),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 5-band Sliders
                SizedBox(
                  height: 155,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(controller.eqBands.length, (idx) {
                      final band = controller.eqBands[idx];
                      return Column(
                        children: [
                          Text(
                            '${band.gainDb >= 0 ? "+" : ""}${band.gainDb.toStringAsFixed(1)}dB',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: band.gainDb,
                                  min: -12.0,
                                  max: 12.0,
                                  activeColor: accent,
                                  onChanged: (v) => controller.updateEqBand(idx, v),
                                ),
                              ),
                            ),
                          ),
                          Text(
                            band.label.split(' ').first,
                            style: TextStyle(fontSize: 11, color: subColor),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
                const Divider(height: 22),

                // Wave Intensity & Theme Row
                Row(
                  children: [
                    Icon(Icons.waves_rounded, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Text('流线波纹跳动幅度:', style: TextStyle(fontSize: 12.5, color: textColor)),
                    Expanded(
                      child: Slider(
                        value: controller.waveIntensity,
                        min: 0.2,
                        max: 1.4,
                        activeColor: accent,
                        onChanged: controller.setWaveIntensity,
                      ),
                    ),
                    Text(
                      '${(controller.waveIntensity * 100).round()}%',
                      style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),

                const SizedBox(height: 6),
                // Theme & Sleep Timer Row
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('毛玻璃主题:', style: TextStyle(fontSize: 12, color: subColor)),
                    for (final preset in VisualThemePreset.values)
                      ChoiceChip(
                        label: Text(preset.name, style: const TextStyle(fontSize: 11.5)),
                        selected: controller.themePreset == preset,
                        selectedColor: accent.withValues(alpha: 0.3),
                        onSelected: (_) => controller.setThemePreset(preset),
                      ),
                    ActionChip(
                      avatar: Icon(
                        isLight ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        size: 15,
                        color: accent,
                      ),
                      label: Text(
                        isLight ? '切换深色极光' : '切换浅色冰川',
                        style: TextStyle(fontSize: 11.5, color: textColor),
                      ),
                      onPressed: controller.toggleGlassBrightnessMode,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.bedtime_rounded, size: 16, color: subColor),
                    Text('睡眠定时:', style: TextStyle(fontSize: 12, color: subColor)),
                    for (final mins in [null, 15, 30, 60])
                      ActionChip(
                        label: Text(
                          mins == null ? '关闭' : '$mins分钟',
                          style: TextStyle(fontSize: 11.5, color: textColor),
                        ),
                        onPressed: () => controller.setSleepTimer(
                          mins == null ? null : Duration(minutes: mins),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Modal sheet displaying the active Playing Queue (正在播放列表), supporting click-to-play and removal.
class PlayingQueueSheet extends StatelessWidget {
  const PlayingQueueSheet({super.key, required this.controller});

  final AudioEngineController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ctrl = controller;
        final isLight = ctrl.isLightGlassMode;
        final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
        final subColor = isLight ? Colors.black54 : Colors.white70;
        final accent = ctrl.activeAuroraColors.first;
        final queue = ctrl.playlist;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: AuraGlassContainer(
            borderRadius: 24,
            blurSigma: 28,
            isLightMode: isLight,
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.queue_music_rounded, color: accent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '正在播放列表 (${queue.length} 首)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: subColor, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (queue.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          '播放列表为空，请从本地歌曲中添加',
                          style: TextStyle(fontSize: 13, color: subColor),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: queue.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final track = queue[index];
                          final isCurrent = track.id == ctrl.currentTrack.id;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => ctrl.selectTrack(track, autoPlay: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: isCurrent
                                    ? accent.withValues(alpha: isLight ? 0.16 : 0.20)
                                    : Colors.white.withValues(alpha: isLight ? 0.3 : 0.05),
                                border: Border.all(
                                  color: isCurrent
                                      ? accent.withValues(alpha: 0.5)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  AlbumCoverAvatar(
                                    coverBytes: track.coverBytes,
                                    colors: track.paletteColors,
                                    size: 36,
                                    borderRadius: 8,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
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
                                                  size: 14,
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
                                                  fontWeight:
                                                      isCurrent ? FontWeight.w700 : FontWeight.w600,
                                                  color: isCurrent ? accent : textColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${track.artist} · ${track.formattedDuration}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11, color: subColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '从播放列表移除',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => ctrl.removeFromPlaylist(track.id),
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 17,
                                      color: subColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
