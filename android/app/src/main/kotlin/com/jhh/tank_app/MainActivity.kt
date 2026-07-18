package com.jhh.tank_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TankBluetooth.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
