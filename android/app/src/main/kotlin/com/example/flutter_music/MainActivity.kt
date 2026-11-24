package com.example.flutter_music

import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.auramusic/native_bridge"
    private var mediaPlayer: MediaPlayer? = null
    private var currentPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val path = call.argument<String>("path") ?: ""
                        val posMs = call.argument<Int>("positionMs") ?: 0
                        val vol = (call.argument<Double>("volume") ?: 0.85).toFloat()
                        try {
                            if (mediaPlayer == null || currentPath != path) {
                                mediaPlayer?.release()
                                mediaPlayer = MediaPlayer().apply {
                                    setDataSource(path)
                                    prepare()
                                }
                                currentPath = path
                            }
                            mediaPlayer?.let { mp ->
                                mp.setVolume(vol, vol)
                                mp.seekTo(posMs)
                                mp.start()
                                result.success(mapOf("durationMs" to mp.duration))
                            } ?: result.success(mapOf("durationMs" to 0))
                        } catch (e: Exception) {
                            result.error("PLAY_ERR", e.message, null)
                        }
                    }
                    "pause" -> {
                        mediaPlayer?.pause()
                        result.success(null)
                    }
                    "stop" -> {
                        mediaPlayer?.stop()
                        mediaPlayer?.release()
                        mediaPlayer = null
                        currentPath = null
                        result.success(null)
                    }
                    "seek" -> {
                        val posMs = call.argument<Int>("positionMs") ?: 0
                        mediaPlayer?.seekTo(posMs)
                        result.success(null)
                    }
                    "setVolume" -> {
                        val vol = (call.argument<Double>("volume") ?: 0.85).toFloat()
                        mediaPlayer?.setVolume(vol, vol)
                        result.success(null)
                    }
                    "getPosition" -> {
                        val mp = mediaPlayer
                        if (mp != null) {
                            result.success(
                                mapOf(
                                    "positionMs" to mp.currentPosition,
                                    "durationMs" to mp.duration
                                )
                            )
                        } else {
                            result.success(mapOf("positionMs" to -1, "durationMs" to -1))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        mediaPlayer?.release()
        mediaPlayer = null
        super.onDestroy()
    }
}
