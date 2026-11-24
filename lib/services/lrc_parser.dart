import 'dart:convert';
import '../models/track.dart';

/// Parses standard `.lrc` synchronized lyrics files and embedded lyric tags.
/// Pure Dart implementation working across Windows, Web, iOS, Android, and HarmonyOS.
class LrcParser {
  static final RegExp _timeTagRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

  /// Parses raw LRC text into a sorted list of [LyricLine] objects.
  static List<LyricLine> parse(String rawLrc) {
    if (rawLrc.trim().isEmpty) return const [];

    final lines = const LineSplitter().convert(rawLrc);
    final parsedEntries = <int, List<String>>{};

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final matches = _timeTagRegex.allMatches(line).toList();
      if (matches.isEmpty) continue;

      final lyricText = line.replaceAll(_timeTagRegex, '').trim();
      if (lyricText.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fracRaw = match.group(3) ?? '0';
        int milliseconds = 0;
        if (fracRaw.length == 1) {
          milliseconds = (int.tryParse(fracRaw) ?? 0) * 100;
        } else if (fracRaw.length == 2) {
          milliseconds = (int.tryParse(fracRaw) ?? 0) * 10;
        } else {
          milliseconds = int.tryParse(fracRaw.padRight(3, '0').substring(0, 3)) ?? 0;
        }

        final totalMs = (minutes * 60 + seconds) * 1000 + milliseconds;
        parsedEntries.putIfAbsent(totalMs, () => []).add(lyricText);
      }
    }

    final sortedKeys = parsedEntries.keys.toList()..sort();
    final result = <LyricLine>[];

    for (final ms in sortedKeys) {
      final texts = parsedEntries[ms]!;
      result.add(
        LyricLine(
          timestamp: Duration(milliseconds: ms),
          text: texts.first,
          translation: texts.length > 1 ? texts.sublist(1).join(' / ') : null,
        ),
      );
    }

    return result;
  }

  /// Decodes raw LRC bytes (UTF-8 with Latin-1 fallback) and parses into [LyricLine]s.
  static List<LyricLine> parseBytes(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes, allowInvalid: true);
    }
    return parse(content);
  }
}
