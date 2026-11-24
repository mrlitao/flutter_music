import 'package:material_ui/material_ui.dart';
import '../models/track.dart';

/// Synchronized scrolling lyrics panel with glowing active line and tap-to-seek support.
class SynchronizedLyricsPanel extends StatefulWidget {
  const SynchronizedLyricsPanel({
    super.key,
    required this.lyrics,
    required this.activeIndex,
    required this.accentColor,
    required this.isLightMode,
    required this.onTapLine,
  });

  final List<LyricLine> lyrics;
  final int activeIndex;
  final Color accentColor;
  final bool isLightMode;
  final ValueChanged<Duration> onTapLine;

  @override
  State<SynchronizedLyricsPanel> createState() => _SynchronizedLyricsPanelState();
}

class _SynchronizedLyricsPanelState extends State<SynchronizedLyricsPanel> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemExtent = 66.0;

  @override
  void didUpdateWidget(covariant SynchronizedLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex && _scrollController.hasClients) {
      final targetOffset = (widget.activeIndex * _itemExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return Center(
        child: Text(
          '暂无同步歌词 · 支持同目录同名 .lrc 自动加载',
          style: TextStyle(
            color: widget.isLightMode ? Colors.black54 : Colors.white54,
            fontSize: 13,
          ),
        ),
      );
    }

    final textColor = widget.isLightMode ? const Color(0xFF0F172A) : Colors.white;
    final mutedColor = widget.isLightMode
        ? const Color(0xFF475569).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.42);

    return ShaderMask(
      shaderCallback: (rect) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.14, 0.86, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 12),
        itemExtent: _itemExtent,
        itemCount: widget.lyrics.length,
        itemBuilder: (context, index) {
          final line = widget.lyrics[index];
          final isCurrent = index == widget.activeIndex;

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onTapLine(line.timestamp),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isCurrent
                    ? widget.accentColor.withValues(alpha: widget.isLightMode ? 0.14 : 0.12)
                    : Colors.transparent,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isCurrent ? 15.5 : 13.5,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? textColor : mutedColor,
                      shadows: isCurrent && !widget.isLightMode
                          ? [
                              Shadow(
                                color: widget.accentColor.withValues(alpha: 0.75),
                                blurRadius: 14,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  if (line.translation != null && line.translation!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        line.translation!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isCurrent
                              ? widget.accentColor.withValues(alpha: 0.95)
                              : mutedColor.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
