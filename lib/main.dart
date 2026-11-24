import 'package:material_ui/material_ui.dart';
import 'screens/home_screen.dart';
import 'services/audio_engine_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AuraMusicApp());
}

/// Root widget for AuraMusic — Cross-Platform Frosted Glass Music Player
/// supporting Windows, iOS, Android, and HarmonyOS NEXT.
class AuraMusicApp extends StatefulWidget {
  const AuraMusicApp({super.key, this.controller});

  final AudioEngineController? controller;

  @override
  State<AuraMusicApp> createState() => _AuraMusicAppState();
}

class _AuraMusicAppState extends State<AuraMusicApp> {
  late final AudioEngineController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AudioEngineController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final isLight = _controller.isLightGlassMode;
        final seed = _controller.activeAuroraColors.first;

        return MaterialApp(
          title: 'AuraMusic 全息毛玻璃音乐播放器',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: isLight ? Brightness.light : Brightness.dark,
            colorSchemeSeed: seed,
            scaffoldBackgroundColor: Colors.transparent,
          ),
          home: AuraMusicHomeScreen(controller: _controller),
        );
      },
    );
  }
}
