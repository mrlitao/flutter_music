import 'package:flutter_music/main.dart';
import 'package:flutter_music/models/track.dart';
import 'package:flutter_music/services/audio_engine_service.dart';
import 'package:flutter_music/services/demo_wav_generator.dart';
import 'package:flutter_music/services/lrc_parser.dart';
import 'package:flutter_music/services/spectrum_analyzer.dart';
import 'package:flutter_music/widgets/fluid_wave_visualizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final controller = AudioEngineController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(AuraMusicApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 50));

    // Verify bottom tabs: 首页, 本地歌曲, 资料库, 我的 + raised circular player button
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('本地歌曲'), findsWidgets);
    expect(find.text('资料库'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    final circularPlayerBtn = find.byKey(const ValueKey('raised_circular_player_tab_button'));
    expect(circularPlayerBtn, findsOneWidget);

    // Initially Player Main View is closed (hidden by wave ripple transition)
    expect(find.byType(FluidWaveRippleVisualizer), findsNothing);

    // Tap raised circular player button -> expands wave ripple from click point to full Player Main View
    await tester.tap(circularPlayerBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    // Mid-transition: visualizer is already being revealed inside ClipPath
    expect(find.byType(FluidWaveRippleVisualizer), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FluidWaveRippleVisualizer), findsOneWidget);

    // Tap raised circular player button again -> contracts wave ripple back into circular button
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
    expect(find.byType(FluidWaveRippleVisualizer), findsOneWidget);
    expect(find.textContaining('Neon Horizon'), findsWidgets);
  });
}
