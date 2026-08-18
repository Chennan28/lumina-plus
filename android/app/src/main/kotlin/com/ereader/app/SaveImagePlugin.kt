package com.ereader.app

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream

/// Saves raw image bytes (original format) to the device photo gallery.
///
/// Android 10+ writes through MediaStore (no permission needed).
/// Android 9 and below writes to the public Pictures/EReader directory
/// (WRITE_EXTERNAL_STORAGE is declared in the manifest with maxSdk 28).
class SaveImagePlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var appContext: Context

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "ereader/save_image")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "saveImage") {
      val bytes = call.argument<ByteArray>("bytes")
      val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
      val fileName = call.argument<String>("fileName")
      if (bytes == null || bytes.isEmpty()) {
        result.error("INVALID_ARGUMENT", "Image bytes are empty", null)
        return
      }
      try {
        val saved = saveToGallery(bytes, mimeType, fileName)
        if (saved) result.success(true)
        else result.error("SAVE_FAILED", "Could not save image to gallery", null)
      } catch (e: Exception) {
        result.error("SAVE_FAILED", e.message ?: "Unknown error", null)
      }
    } else {
      result.notImplemented()
    }
  }

  private fun saveToGallery(bytes: ByteArray, mimeType: String, fileName: String?): Boolean {
    // Keep only safe filename characters.
    val safeBase = (fileName ?: "").replace(Regex("[^a-zA-Z0-9._\\-]"), "_")
    val ext = when {
      mimeType.contains("svg") -> "svg"
      mimeType.contains("png") -> "png"
      mimeType.contains("webp") -> "webp"
      mimeType.contains("gif") -> "gif"
      else -> "jpg"
    }
    val base = if (safeBase.isNotBlank()) safeBase else "ereader_image_${System.currentTimeMillis()}"
    val fullName = if (base.contains('.')) base else "$base.$ext"

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, fullName)
        put(MediaStore.Images.Media.MIME_TYPE, mimeType)
        put(
          MediaStore.Images.Media.RELATIVE_PATH,
          Environment.DIRECTORY_PICTURES + "/EReader",
        )
        put(MediaStore.Images.Media.IS_PENDING, 1)
      }
      val resolver = appContext.contentResolver
      val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
          ?: return false
      resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return false
      values.clear()
      values.put(MediaStore.Images.Media.IS_PENDING, 0)
      resolver.update(uri, values, null, null)
      return true
    } else {
      // API 28 and below: public Pictures/EReader directory.
      val dir = File(
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
        "EReader",
      )
      if (!dir.exists() && !dir.mkdirs()) return false
      val out = File(dir, fullName)
      FileOutputStream(out).use { it.write(bytes) }
      appContext.sendBroadcast(
        Intent(
          Intent.ACTION_MEDIA_SCANNER_SCAN_FILE,
          Uri.fromFile(out),
        ),
      )
      return true
    }
  }
}
