#import "GeneratedPluginRegistrant.h"
#import <AVFoundation/AVFoundation.h>
#import <Flutter/Flutter.h>

@interface AuraMusicIosBridge : NSObject
+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry;
@end

@implementation AuraMusicIosBridge {
  AVAudioPlayer* _audioPlayer;
  NSString* _currentPath;
}

+ (instancetype)sharedInstance {
  static AuraMusicIosBridge* instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[AuraMusicIosBridge alloc] init];
  });
  return instance;
}

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  NSObject<FlutterPluginRegistrar>* registrar =
      [registry registrarForPlugin:@"AuraMusicIosBridge"];
  if (!registrar) return;
  FlutterMethodChannel* channel =
      [FlutterMethodChannel methodChannelWithName:@"com.auramusic/native_bridge"
                                  binaryMessenger:[registrar messenger]];
  [[self sharedInstance] setupChannel:channel];
}

- (void)setupChannel:(FlutterMethodChannel*)channel {
  __weak typeof(self) weakSelf = self;
  [channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
      result(nil);
      return;
    }
    NSDictionary* args = [call.arguments isKindOfClass:[NSDictionary class]]
                             ? (NSDictionary*)call.arguments
                             : nil;
    NSString* method = call.method;

    if ([method isEqualToString:@"play"]) {
      NSString* path = args[@"path"] ?: @"";
      NSNumber* posMsNum = args[@"positionMs"] ?: @(0);
      NSNumber* volNum = args[@"volume"] ?: @(0.85);
      NSError* err = nil;
      if (!strongSelf->_audioPlayer || ![strongSelf->_currentPath isEqualToString:path]) {
        NSURL* url = [NSURL fileURLWithPath:path];
        strongSelf->_audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&err];
        [strongSelf->_audioPlayer prepareToPlay];
        strongSelf->_currentPath = path;
      }
      if (strongSelf->_audioPlayer && !err) {
        strongSelf->_audioPlayer.volume = [volNum floatValue];
        strongSelf->_audioPlayer.currentTime = [posMsNum doubleValue] / 1000.0;
        [strongSelf->_audioPlayer play];
        int durationMs = (int)(strongSelf->_audioPlayer.duration * 1000.0);
        result(@{@"durationMs" : @(durationMs)});
      } else {
        result(@{@"durationMs" : @(0)});
      }
    } else if ([method isEqualToString:@"pause"]) {
      [strongSelf->_audioPlayer pause];
      result(nil);
    } else if ([method isEqualToString:@"stop"]) {
      [strongSelf->_audioPlayer stop];
      strongSelf->_audioPlayer = nil;
      strongSelf->_currentPath = nil;
      result(nil);
    } else if ([method isEqualToString:@"seek"]) {
      NSNumber* posMsNum = args[@"positionMs"] ?: @(0);
      if (strongSelf->_audioPlayer) {
        strongSelf->_audioPlayer.currentTime = [posMsNum doubleValue] / 1000.0;
      }
      result(nil);
    } else if ([method isEqualToString:@"setVolume"]) {
      NSNumber* volNum = args[@"volume"] ?: @(0.85);
      if (strongSelf->_audioPlayer) {
        strongSelf->_audioPlayer.volume = [volNum floatValue];
      }
      result(nil);
    } else if ([method isEqualToString:@"getPosition"]) {
      if (strongSelf->_audioPlayer) {
        int posMs = (int)(strongSelf->_audioPlayer.currentTime * 1000.0);
        int durMs = (int)(strongSelf->_audioPlayer.duration * 1000.0);
        result(@{@"positionMs" : @(posMs), @"durationMs" : @(durMs)});
      } else {
        result(@{@"positionMs" : @(-1), @"durationMs" : @(-1)});
      }
    } else {
      result(FlutterMethodNotImplemented);
    }
  }];
}

@end
