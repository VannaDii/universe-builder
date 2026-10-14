package com.example.universe_builder

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import java.io.File
import java.util.UUID
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var fileResult: MethodChannel.Result? = null
    private var pickedLimit = 10L * 1024 * 1024
    private var pickingText = false
    private var backupPath: String? = null
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
                    "saveBackup", "openBackup" -> {
                        val path = call.argument<String>(if (call.method == "saveBackup") "source" else "destination")
                        if (fileResult != null || path == null) {
                            result.error("unavailable", "Backup file picker unavailable.", null)
                        } else {
                            fileResult = result
                            backupPath = path
                            try {
                                val saving = call.method == "saveBackup"
                                val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/octet-stream"
                                    if (saving) putExtra(Intent.EXTRA_TITLE, File(path).name)
                                    else type = "*/*"
                                }
                                startActivityForResult(intent, if (saving) 4102 else 4103)
                            } catch (_: Exception) {
                                fileResult = null
                                backupPath = null
                                result.error("unavailable", "Backup file picker unavailable.", null)
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
        if (requestCode !in 4101..4103) return
        val result = fileResult ?: return
        if (resultCode != Activity.RESULT_OK) {
            fileResult = null
            backupPath = null
            result.success(if (requestCode == 4103) false else null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            fileResult = null
            result.error("unavailable", "Could not read the selected file.", null)
            return
        }
        if (requestCode != 4101) {
            val path = backupPath
            if (path == null) {
                fileResult = null
                result.error("unavailable", "Backup path unavailable.", null)
            } else {
                copyBackup(uri, path, requestCode == 4102, result)
            }
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

    private fun copyBackup(uri: android.net.Uri, path: String, saving: Boolean, result: MethodChannel.Result) {
        Thread {
            val file = File(path)
            var created = false
            try {
                val limit = 8L * 1024 * 1024 * 1024
                if (saving && (!file.isFile || file.length() > limit)) throw IllegalArgumentException()
                if (!saving) {
                    if (!file.createNewFile()) throw IllegalStateException()
                    created = true
                }
                val input = if (saving) file.inputStream() else contentResolver.openInputStream(uri)
                input?.use { source ->
                    val output = if (saving) contentResolver.openOutputStream(uri, "wt") else file.outputStream()
                    output?.use { destination ->
                        val buffer = ByteArray(65536)
                        var total = 0L
                        while (true) {
                            val count = source.read(buffer)
                            if (count < 0) break
                            total += count
                            if (total > limit) throw IllegalArgumentException()
                            destination.write(buffer, 0, count)
                        }
                        if (total == 0L) throw IllegalArgumentException()
                    } ?: throw IllegalArgumentException()
                } ?: throw IllegalArgumentException()
                val name = if (saving) runCatching {
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        if (it.moveToFirst()) it.getString(0) else null
                    }
                }.getOrNull() ?: "Universe Builder backup.sqlite" else null
                runOnUiThread {
                    if (fileResult === result) {
                        fileResult = null
                        backupPath = null
                        result.success(if (saving) name else true)
                    } else if (!saving && created) {
                        file.delete()
                    }
                }
            } catch (_: Exception) {
                if (saving) runCatching { DocumentsContract.deleteDocument(contentResolver, uri) }
                else if (created) file.delete()
                runOnUiThread {
                    if (fileResult === result) {
                        fileResult = null
                        backupPath = null
                        result.error("copy_failed", "Could not copy this backup file.", null)
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
