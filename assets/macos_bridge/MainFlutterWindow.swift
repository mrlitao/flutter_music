import AVFoundation
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var avPlayer: AVPlayer?
  private var currentPath: String?
  private var auraChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 360, height: 600)
    self.title = "AuraMusic"

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerAuraMusicBridge(flutterViewController: flutterViewController)

    super.awakeFromNib()
  }

  private func registerAuraMusicBridge(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.auramusic/native_bridge",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.auraChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any]

      switch call.method {
      case "play":
        let path = args?["path"] as? String ?? ""
        let posMs = args?["positionMs"] as? Int ?? 0
        let volume = Float(args?["volume"] as? Double ?? 0.85)
        let speed = Float(args?["speed"] as? Double ?? 1.0)

        let url = URL(fileURLWithPath: path)
        if self.avPlayer == nil || self.currentPath != path {
          let item = AVPlayerItem(url: url)
          self.avPlayer = AVPlayer(playerItem: item)
          self.currentPath = path
        }

        if let player = self.avPlayer {
          player.volume = volume
          let targetTime = CMTime(value: CMTimeValue(posMs), timescale: 1000)
          player.seek(to: targetTime)
          player.play()
          player.rate = speed

          var durationMs = 0
          if let dur = player.currentItem?.asset.duration, dur.isNumeric {
            let sec = CMTimeGetSeconds(dur)
            if !sec.isNaN && !sec.isInfinite && sec > 0 {
              durationMs = Int(sec * 1000.0)
            }
          }
          result(["durationMs": durationMs, "ok": true])
        } else {
          result(["durationMs": 0, "ok": false])
        }

      case "pause":
        self.avPlayer?.pause()
        result(nil)

      case "stop":
        self.avPlayer?.pause()
        self.avPlayer = nil
        self.currentPath = nil
        result(nil)

      case "seek":
        let posMs = args?["positionMs"] as? Int ?? 0
        let targetTime = CMTime(value: CMTimeValue(posMs), timescale: 1000)
        self.avPlayer?.seek(to: targetTime)
        result(nil)

      case "setVolume":
        let volume = Float(args?["volume"] as? Double ?? 0.85)
        self.avPlayer?.volume = volume
        result(nil)

      case "setSpeed":
        let speed = Float(args?["speed"] as? Double ?? 1.0)
        if let player = self.avPlayer, player.rate != 0 {
          player.rate = speed
        }
        result(nil)

      case "getPosition":
        if let player = self.avPlayer {
          let posSec = CMTimeGetSeconds(player.currentTime())
          let posMs = (!posSec.isNaN && posSec >= 0) ? Int(posSec * 1000.0) : -1
          var lenMs = -1
          if let dur = player.currentItem?.duration, dur.isNumeric {
            let durSec = CMTimeGetSeconds(dur)
            if !durSec.isNaN && !durSec.isInfinite && durSec > 0 {
              lenMs = Int(durSec * 1000.0)
            }
          }
          result(["positionMs": posMs, "durationMs": lenMs])
        } else {
          result(["positionMs": -1, "durationMs": -1])
        }

      case "pickFolder":
        DispatchQueue.main.async {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          panel.allowsMultipleSelection = false
          panel.prompt = "选择音乐文件夹"
          if panel.runModal() == .OK, let url = panel.url {
            result(url.path)
          } else {
            result(nil)
          }
        }

      case "pickAudioFiles":
        DispatchQueue.main.async {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = false
          panel.canChooseFiles = true
          panel.allowsMultipleSelection = true
          panel.prompt = "导入音乐"
          panel.allowedFileTypes = ["mp3", "mp4", "flac", "wav", "m4a", "aac", "ogg", "wma"]
          if panel.runModal() == .OK {
            result(panel.urls.map { $0.path })
          } else {
            result([String]())
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
