package com.legendarios.hakuna_connect

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.legendarios.hakuna_connect/hce"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPayload" -> {
                    val bytes = (call.arguments as? ByteArray)
                    HceBridge.setPayload(bytes)
                    result.success(null)
                }
                "clearPayload" -> {
                    HceBridge.setPayload(null)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        HceBridge.setOnDeactivatedListener { reason ->
            runOnUiThread { channel.invokeMethod("onDeactivated", reason) }
        }
    }
}
