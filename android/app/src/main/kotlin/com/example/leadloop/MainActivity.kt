package com.example.leadloop

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val exportChannel = "enquiry_tracker/export_email"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "composeWithAttachment") {
                    composeEmailWithAttachment(call, result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun composeEmailWithAttachment(call: MethodCall, result: MethodChannel.Result) {
        val recipient = call.argument<String>("recipient")?.trim()
        val subject = call.argument<String>("subject") ?: "Enquiry Tracker customer follow-ups"
        val body = call.argument<String>("body") ?: ""
        val rawFileName = call.argument<String>("fileName") ?: "enquiry_tracker_export.xlsx"
        val bytes = call.argument<ByteArray>("bytes")

        if (recipient.isNullOrEmpty() || bytes == null) {
            result.error("invalid_export", "An email recipient and Excel file are required.", null)
            return
        }

        try {
            val fileName = rawFileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val exportDirectory = File(cacheDir, "exports").apply { mkdirs() }
            val exportFile = File(exportDirectory, fileName)
            exportFile.outputStream().use { stream -> stream.write(bytes) }
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.exportfiles",
                exportFile,
            )

            val emailIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                putExtra(Intent.EXTRA_EMAIL, arrayOf(recipient))
                putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, body)
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(emailIntent, "Send Excel export"))
            result.success(true)
        } catch (error: Exception) {
            result.error("email_export_failed", error.message, null)
        }
    }
}
