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
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

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
                        '导入本机音乐资源 (Windows / iOS / Android / 鸿蒙)',
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

                // Quick Native Action Buttons
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
                              await ctrl.pickAndScanFolder();
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
                              await ctrl.pickAndImportAudioFiles();
                            },
                    ),
                    _buildActionButton(
                      icon: Icons.sync_rounded,
                      label: '扫描系统默认音乐库',
                      accent: ctrl.activeAuroraColors[2],
                      isLight: isLight,
                      onTap: ctrl.isScanning
                          ? null
                          : () async {
                              await ctrl.scanDefaultSystemMusicFolders();
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Manual Directory Input Row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pathController,
                        style: TextStyle(color: textColor, fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: r'或输入本机音乐目录路径 (例如 C:\Users\Music 或 /sdcard/Music)',
                          hintStyle: TextStyle(color: subColor.withValues(alpha: 0.5), fontSize: 12),
                          filled: true,
                          fillColor: isLight
                              ? Colors.black.withValues(alpha: 0.05)
                              : Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: ctrl.isScanning
                          ? null
                          : () async {
                              final input = _pathController.text.trim();
                              if (input.isNotEmpty) {
                                await ctrl.scanCustomDirectory(input);
                              }
                            },
                      icon: const Icon(Icons.search_rounded, size: 17, color: Colors.black87),
                      label: const Text(
                        '扫描路径',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
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
                        ctrl.statusMessage,
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
