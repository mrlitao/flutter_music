import media from '@ohos.multimedia.media';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

/**
 * HarmonyOS NEXT (OpenHarmony) Native Audio & File Picker Bridge for AuraMusic.
 * Registers MethodChannel `com.auramusic/native_bridge` to match Windows, iOS, and Android.
 */
export default class AuraMusicPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private avPlayer: media.AVPlayer | null = null;
  private currentPath: string = '';

  getUniqueClassName(): string {
    return 'AuraMusicPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'com.auramusic/native_bridge');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.avPlayer?.release();
    this.avPlayer = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      switch (call.method) {
        case 'play': {
          const path = call.argument('path') as string;
          const posMs = (call.argument('positionMs') as number) ?? 0;
          const volume = (call.argument('volume') as number) ?? 0.85;

          if (this.avPlayer == null) {
            this.avPlayer = await media.createAVPlayer();
          }
          if (this.currentPath !== path) {
            await this.avPlayer.reset();
            const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
            this.avPlayer.fdSrc = { fd: file.fd };
            await this.avPlayer.prepare();
            this.currentPath = path;
          }
          this.avPlayer.setVolume(volume);
          this.avPlayer.seek(posMs);
          await this.avPlayer.play();
          result.success({ durationMs: this.avPlayer.duration });
          break;
        }
        case 'pause': {
          await this.avPlayer?.pause();
          result.success(null);
          break;
        }
        case 'stop': {
          await this.avPlayer?.stop();
          await this.avPlayer?.reset();
          this.currentPath = '';
          result.success(null);
          break;
        }
        case 'seek': {
          const posMs = (call.argument('positionMs') as number) ?? 0;
          this.avPlayer?.seek(posMs);
          result.success(null);
          break;
        }
        case 'setVolume': {
          const volume = (call.argument('volume') as number) ?? 0.85;
          this.avPlayer?.setVolume(volume);
          result.success(null);
          break;
        }
        case 'getPosition': {
          if (this.avPlayer != null) {
            result.success({
              positionMs: this.avPlayer.currentTime,
              durationMs: this.avPlayer.duration,
            });
          } else {
            result.success({ positionMs: -1, durationMs: -1 });
          }
          break;
        }
        case 'pickAudioFiles': {
          const audioPicker = new picker.AudioViewPicker();
          const selectOpts = new picker.AudioSelectOptions();
          const uris = await audioPicker.select(selectOpts);
          result.success(uris);
          break;
        }
        default:
          result.notImplemented();
          break;
      }
    } catch (err) {
      result.error('OHOS_AUDIO_ERR', JSON.stringify(err), null);
    }
  }
}
