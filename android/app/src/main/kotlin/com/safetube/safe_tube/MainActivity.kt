package com.safetube.safe_tube

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val worker = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "channelVideos" -> {
                        val channelId = call.argument<String>("channelId")
                        if (channelId.isNullOrEmpty()) {
                            result.error("no_channel_id", "channelId is required", null)
                            return@setMethodCallHandler
                        }
                        val limit = call.argument<Int>("limit") ?: 200
                        val stopAtIds =
                            call.argument<List<String>>("stopAtIds")?.toSet() ?: emptySet()

                        // NewPipeExtractor does its network work on the calling
                        // thread, so it must never run on the platform thread.
                        worker.execute {
                            try {
                                val videos =
                                    NewPipeBridge.channelVideos(channelId, limit, stopAtIds)
                                main.post { result.success(videos) }
                            } catch (e: Throwable) {
                                main.post {
                                    result.error(
                                        "extract_failed",
                                        e.message ?: e.javaClass.simpleName,
                                        null,
                                    )
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "kidtube/newpipe"
    }
}
