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
    private var fileResult: MethodChannel.Result? = null
    private var pickedLimit = 10L * 1024 * 1024
    private var pickingText = false
    private val pickedFiles = mutableSetOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "universe_builder/backup_files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage", "pickSourceText" -> {
                        if (fileResult != null) {
                            result.error("busy", "A file picker is already open.", null)
                        } else {
                            fileResult = result
                            pickingText = call.method == "pickSourceText"
                            pickedLimit = if (pickingText) 1024L * 1024 else 10L * 1024 * 1024
                            try {
                                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = if (pickingText) "text/*" else "image/*"
                                    if (!pickingText) putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/png", "image/jpeg", "image/webp"))
                                }
                                startActivityForResult(intent, 4101)
                            } catch (_: Exception) {
                                fileResult = null
                                result.error("unavailable", "File picker unavailable.", null)
                            }
                        }
                    }
                    "releasePickedFile" -> {
                        val path = call.argument<String>("source")
                        if (path != null && pickedFiles.remove(path)) {
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
        val result = fileResult ?: return
        if (resultCode != Activity.RESULT_OK) {
            fileResult = null
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            fileResult = null
            result.error("unavailable", "Could not read the selected file.", null)
            return
        }
        val limit = pickedLimit
        val isText = pickingText
        Thread {
            var directory: File? = null
            try {
                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                } ?: throw IllegalArgumentException()
                if (name.isEmpty() || name == "." || name == ".." || name.contains('/') || name.contains('\\') || name.contains('\u0000')) {
                    throw IllegalArgumentException()
                }
                directory = File(cacheDir, "ub-picked-files/${UUID.randomUUID()}")
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
                            if (total > limit) throw IllegalArgumentException()
                            output.write(buffer, 0, count)
                        }
                        if (total == 0L && !isText) throw IllegalArgumentException()
                    }
                } ?: throw IllegalArgumentException()
                runOnUiThread {
                    if (fileResult === result) {
                        pickedFiles.add(file.absolutePath)
                        fileResult = null
                        result.success(file.absolutePath)
                    } else {
                        file.parentFile?.deleteRecursively()
                    }
                }
            } catch (_: Exception) {
                directory?.deleteRecursively()
                runOnUiThread {
                    if (fileResult === result) {
                        fileResult = null
                        result.error("invalid_file", if (isText) "Choose a readable UTF-8 text file up to 1 MiB." else "Choose a readable PNG, JPEG or WebP image up to 10 MiB.", null)
                    }
                }
            }
        }.start()
    }

    override fun onDestroy() {
        fileResult?.error("unavailable", "File selection was interrupted.", null)
        fileResult = null
        super.onDestroy()
    }
}
