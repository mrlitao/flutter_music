import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_music/main.dart';
import 'package:flutter_music/models/track.dart';
import 'package:flutter_music/services/audio_engine_service.dart';
import 'package:flutter_music/services/demo_wav_generator.dart';
import 'package:flutter_music/services/lrc_parser.dart';
import 'package:flutter_music/services/metadata_parser.dart';
import 'package:flutter_music/services/spectrum_analyzer.dart';
import 'package:flutter_music/widgets/fluid_wave_visualizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

/// Builds a valid ISO Base Media (.mp4) header with `ftyp` and `moov`/`mvhd` boxes
/// encoding [durationSeconds] at [timescale].
Uint8List buildTestMp4Header({int timescale = 48000, int durationSeconds = 185}) {
  final buffer = Uint8List(128);
  final bd = ByteData.sublistView(buffer);

  // ftyp box (24 bytes)
  bd.setUint32(0, 24, Endian.big);
  buffer.setRange(4, 8, 'ftyp'.codeUnits);
  buffer.setRange(8, 12, 'mp42'.codeUnits);

  // moov box header at offset 24 (64 bytes)
  bd.setUint32(24, 64, Endian.big);
  buffer.setRange(28, 32, 'moov'.codeUnits);

  // mvhd box at offset 32 (version 0)
  bd.setUint32(32, 56, Endian.big);
  buffer.setRange(36, 40, 'mvhd'.codeUnits);
  buffer[40] = 0; // version 0
  // timescale at offset 36 + 16 = 52
  bd.setUint32(52, timescale, Endian.big);
  // duration at offset 36 + 20 = 56
  bd.setUint32(56, timescale * durationSeconds, Endian.big);

  return buffer;
}

void main() {
  test('LrcParser accurately parses timestamps and bilingual lyric lines', () {
    const sampleLrc = '''
[00:00.00]穿过城市夜色与全息毛玻璃微光
[00:00.00]Through city nightscapes and holographic frosted light
[00:04.50]流线波纹在耳畔随低频节拍绽放 ♪
''';
    final lines = LrcParser.parse(sampleLrc);
    expect(lines.length, 2);
    expect(lines[0].timestamp, Duration.zero);
    expect(lines[0].text, '穿过城市夜色与全息毛玻璃微光');
    expect(lines[0].translation, 'Through city nightscapes and holographic frosted light');
    expect(lines[1].timestamp, const Duration(milliseconds: 4500));
  });

  test('AudioMetadataParser & LocalMusicScanner support .mp4 files and parse mvhd duration', () async {
    final mp4Header = buildTestMp4Header(timescale: 48000, durationSeconds: 185);
    final track = AudioMetadataParser.parseBytes(
      id: 'test_song.mp4',
      filePath: r'C:\Music\周杰伦 - 晴天.mp4',
      fileName: '周杰伦 - 晴天.mp4',
      folderPath: r'C:\Music',
      fileSize: 5920000,
      headerBytes: mp4Header,
    );

    expect(track.artist, '周杰伦');
    expect(track.title, '晴天');
    expect(track.duration, const Duration(seconds: 185));
    expect(track.formattedDuration, '03:05');
    expect(track.formatBadge, contains('MP4'));
    expect(track.lyrics, isEmpty);

    // Also test scanning a real temporary directory containing an .mp4 file
    final tempDir = await Directory.systemTemp.createTemp('auramusic_mp4_test_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final mp4File = File(p.join(tempDir.path, 'Aether - Aurora Live.mp4'));
    await mp4File.writeAsBytes(mp4Header, flush: true);

    final controller = AudioEngineController();
    addTearDown(controller.dispose);

    final addedCount = await controller.scanCustomDirectory(tempDir.path);
    expect(addedCount, 1);
    expect(controller.allTracks.any((t) => t.title == 'Aurora Live'), isTrue);

    // Test deleteTrack removes imported song
    final importedTrack = controller.allTracks.firstWhere((t) => t.title == 'Aurora Live');
    await controller.deleteTrack(importedTrack.id);
    expect(controller.allTracks.any((t) => t.title == 'Aurora Live'), isFalse);

    // Test playlist & previous/next order
    final firstId = controller.playlist.first.id;
    final secondId = controller.playlist[1].id;
    await controller.selectTrack(controller.playlist.first, autoPlay: true);
    expect(controller.currentTrack.id, firstId);
    await controller.nextTrack();
    expect(controller.currentTrack.id, secondId);
    await controller.previousTrack();
    expect(controller.currentTrack.id, firstId);

    // Test toggleMute mutes and restores previous volume
    await controller.setVolume(0.65);
    await controller.toggleMute();
    expect(controller.volume, 0.0);
    await controller.toggleMute();
    expect(controller.volume, 0.65);
  });

  test('60FPS spectrumNotifier updates without triggering full-app rebuild stutter', () async {
    final controller = AudioEngineController();
    addTearDown(controller.dispose);

    // Wait for initial default folder scan to settle
    while (controller.isScanning) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));

    int fullTreeRebuildCount = 0;
    int spectrumFrameCount = 0;

    controller.addListener(() {
      fullTreeRebuildCount++;
    });
    controller.spectrumNotifier.addListener(() {
      spectrumFrameCount++;
    });

    await Future<void>.delayed(const Duration(milliseconds: 220));
    // Spectrum notifier ticks at 60FPS while full-tree rebuilds stay 0!
    expect(spectrumFrameCount, greaterThanOrEqualTo(5));
    expect(fullTreeRebuildCount, 0);
  });

  test('DemoWavGenerator & SpectrumAnalyzer compute valid 32-band FFT spectrum frames', () async {
    final tracks = DemoWavGenerator.buildShowcaseTracks();
    expect(tracks.length, 4);

    final wavBytes = DemoWavGenerator.getOrGenerateWavBytes(0);
    expect(wavBytes.length, greaterThan(44));
    expect(String.fromCharCodes(wavBytes.sublist(0, 4)), 'RIFF');

    final analyzer = SpectrumAnalyzer();
    await analyzer.prepareForTrack(tracks.first);
    final frame = analyzer.computeFrame(
      isPlaying: true,
      position: const Duration(seconds: 2),
      track: tracks.first,
      eqBands: const [
        EqualizerBand(label: '60Hz', frequencyHz: 60, gainDb: 3.0),
        EqualizerBand(label: '1kHz', frequencyHz: 1000, gainDb: 1.0),
      ],
      intensity: 0.85,
    );

    expect(frame.bins.length, 32);
    expect(frame.pitchClasses.length, 12);
    expect(frame.pitchTrail1.length, 12);
    expect(frame.pitchTrail2.length, 12);
    expect(frame.bassEnergy, inInclusiveRange(0.02, 1.0));
    expect(frame.midEnergy, inInclusiveRange(0.02, 1.0));
    expect(frame.trebleEnergy, inInclusiveRange(0.02, 1.0));
  });

  test('AudioEngineController supports all 8 TrackSortOption modes', () {
    final controller = AudioEngineController();
    addTearDown(controller.dispose);

    controller.setSortOption(TrackSortOption.playCountDesc);
    final byPlayDesc = controller.filteredTracks;
    expect(byPlayDesc.first.playCount, greaterThanOrEqualTo(byPlayDesc.last.playCount));

    controller.setSortOption(TrackSortOption.playCountAsc);
    final byPlayAsc = controller.filteredTracks;
    expect(byPlayAsc.first.playCount, lessThanOrEqualTo(byPlayAsc.last.playCount));

    controller.setSortOption(TrackSortOption.titleAsc);
    final byTitleAsc = controller.filteredTracks;
    expect(
      byTitleAsc.first.title.toLowerCase().compareTo(byTitleAsc.last.title.toLowerCase()),
      lessThanOrEqualTo(0),
    );
  });

  testWidgets('Small Window (Mobile) renders 5-entry bottom TabBar & toggles raised circular player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = AudioEngineController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(AuraMusicApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('本地歌曲'), findsWidgets);
    expect(find.text('资料库'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byKey(const ValueKey('az_anchor_bar')), findsOneWidget);
    final circularPlayerBtn = find.byKey(const ValueKey('raised_circular_player_tab_button'));
    expect(circularPlayerBtn, findsOneWidget);

    expect(find.byType(FluidWaveRippleVisualizer), findsNothing);

    await tester.tap(circularPlayerBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(FluidWaveRippleVisualizer), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FluidWaveRippleVisualizer), findsOneWidget);

    await tester.tap(circularPlayerBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    expect(find.byType(FluidWaveRippleVisualizer), findsNothing);
    expect(find.byKey(const ValueKey('tab_local_songs')), findsOneWidget);
  });

  testWidgets('AuraMusicApp renders Desktop Widescreen & FluidWaveRippleVisualizer', (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = AudioEngineController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(AuraMusicApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('AuraMusic'), findsOneWidget);
    expect(find.text('本地音乐播放器'), findsOneWidget);
    expect(find.byType(FluidWaveRippleVisualizer), findsOneWidget);
    expect(find.textContaining('Neon Horizon'), findsWidgets);
  });

  testWidgets('Medium Desktop (860-930px) renders cleanly without layout overflow', (tester) async {
    tester.view.physicalSize = const Size(880, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = AudioEngineController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(AuraMusicApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('本地音乐播放器'), findsOneWidget);
    expect(find.byType(FluidWaveRippleVisualizer), findsOneWidget);
  });
}
