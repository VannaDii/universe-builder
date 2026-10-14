package com.example.universe_builder

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import java.io.File
import java.util.UUID
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var imageResult: MethodChannel.Result? = null
    private val pickedImages = mutableSetOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "universe_builder/backup_files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> {
                        if (imageResult != null) {
                            result.error("busy", "An image picker is already open.", null)
                        } else {
                            imageResult = result
                            try {
                                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "image/*"
                                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/png", "image/jpeg", "image/webp"))
                                }
                                startActivityForResult(intent, 4101)
                            } catch (_: Exception) {
                                imageResult = null
                                result.error("unavailable", "Image picker unavailable.", null)
                            }
                        }
                    }
                    "releasePickedImage" -> {
                        val path = call.argument<String>("source")
                        if (path != null && pickedImages.remove(path)) {
                            File(path).parentFile?.deleteRecursively()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "universe_builder/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "installationRoot") {
                    result.success(File(noBackupFilesDir, "universe-builder/installation").absolutePath)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4101) return
        val result = imageResult ?: return
        if (resultCode != Activity.RESULT_OK) {
            imageResult = null
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            imageResult = null
            result.error("unavailable", "Could not read the selected image.", null)
            return
        }
        Thread {
            var directory: File? = null
            try {
                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                } ?: throw IllegalArgumentException()
                if (name.isEmpty() || name == "." || name == ".." || name.contains('/') || name.contains('\\') || name.contains('\u0000')) {
                    throw IllegalArgumentException()
                }
                directory = File(cacheDir, "ub-picked-images/${UUID.randomUUID()}")
                if (!directory.mkdirs()) throw IllegalStateException()
                val file = File(directory, name)
                contentResolver.openInputStream(uri)?.use { input ->
                    file.outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        var total = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            if (total > 10L * 1024 * 1024) throw IllegalArgumentException()
                            output.write(buffer, 0, count)
                        }
                        if (total == 0L) throw IllegalArgumentException()
                    }
                } ?: throw IllegalArgumentException()
                runOnUiThread {
                    if (imageResult === result) {
                        pickedImages.add(file.absolutePath)
                        imageResult = null
                        result.success(file.absolutePath)
                    } else {
                        file.parentFile?.deleteRecursively()
                    }
                }
            } catch (_: Exception) {
                directory?.deleteRecursively()
                runOnUiThread {
                    if (imageResult === result) {
                        imageResult = null
                        result.error("invalid_file", "Choose a readable PNG, JPEG or WebP image up to 10 MiB.", null)
                    }
                }
            }
        }.start()
    }

    override fun onDestroy() {
        imageResult?.error("unavailable", "Image selection was interrupted.", null)
        imageResult = null
        super.onDestroy()
    }
}
