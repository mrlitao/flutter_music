import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioPlayer: AVAudioPlayer?
  private var currentPath: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.auramusic/native_bridge",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any]

      switch call.method {
      case "play":
        let path = args?["path"] as? String ?? ""
        let posMs = args?["positionMs"] as? Int ?? 0
        let volume = Float(args?["volume"] as? Double ?? 0.85)
        do {
          if self.audioPlayer == nil || self.currentPath != path {
            let url = URL(fileURLWithPath: path)
            self.audioPlayer = try AVAudioPlayer(contentsOf: url)
            self.audioPlayer?.prepareToPlay()
            self.currentPath = path
          }
          if let player = self.audioPlayer {
            player.volume = volume
            player.currentTime = TimeInterval(posMs) / 1000.0
            player.play()
            let durationMs = Int(player.duration * 1000.0)
            result(["durationMs": durationMs])
          } else {
            result(["durationMs": 0])
          }
        } catch {
          result(FlutterError(code: "PLAY_ERR", message: error.localizedDescription, details: nil))
        }
      case "pause":
        self.audioPlayer?.pause()
        result(nil)
      case "stop":
        self.audioPlayer?.stop()
        self.audioPlayer = nil
        self.currentPath = nil
        result(nil)
      case "seek":
        let posMs = args?["positionMs"] as? Int ?? 0
        self.audioPlayer?.currentTime = TimeInterval(posMs) / 1000.0
        result(nil)
      case "setVolume":
        let volume = Float(args?["volume"] as? Double ?? 0.85)
        self.audioPlayer?.volume = volume
        result(nil)
      case "getPosition":
        if let player = self.audioPlayer {
          result([
            "positionMs": Int(player.currentTime * 1000.0),
            "durationMs": Int(player.duration * 1000.0),
          ])
        } else {
          result(["positionMs": -1, "durationMs": -1])
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
