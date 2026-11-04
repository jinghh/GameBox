package com.jhh.tank_app

import android.content.pm.ActivityInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 蓝牙联机通道唯一的注册入口；漏注册会让联机页抛 MissingPluginException。
        TankBluetooth.register(this, flutterEngine.dartExecutor.binaryMessenger)
        val channel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/orientation")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "portrait" -> {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    result.success(null)
                }
                "landscape" -> {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    result.success(null)
                }
                "sensor" -> {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
