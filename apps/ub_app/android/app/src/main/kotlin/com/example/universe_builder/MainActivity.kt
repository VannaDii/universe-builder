package com.example.universe_builder

import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "universe_builder/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "installationRoot") {
                    result.success(File(noBackupFilesDir, "universe-builder/installation").absolutePath)
                } else {
                    result.notImplemented()
                }
            }
    }
}
