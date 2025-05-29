package com.example.docscanner

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.docscanner/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        scanFile(filePath, result)
                    } else {
                        result.error("INVALID_PATH", "Se requiere una ruta de archivo válida", null)
                    }
                }
                "saveImageToGallery" -> {
                    val imageBytes = call.argument<ByteArray>("imageBytes")
                    val albumName = call.argument<String>("albumName") ?: "DocScanner"
                    val fileName = call.argument<String>("fileName") ?: "scan_${System.currentTimeMillis()}.jpg"
                    
                    if (imageBytes != null) {
                        saveImageToGallery(imageBytes, albumName, fileName, result)
                    } else {
                        result.error("INVALID_DATA", "Se requieren datos de imagen", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun scanFile(path: String, result: Result) {
        try {
            MediaScannerConnection.scanFile(
                context,
                arrayOf(path),
                arrayOf("image/jpeg"),
                { _, uri -> 
                    result.success(uri?.toString() ?: true)
                }
            )
        } catch (e: Exception) {
            result.error("SCAN_ERROR", "Error al escanear archivo: ${e.message}", null)
        }
    }
    
    private fun saveImageToGallery(imageBytes: ByteArray, albumName: String, fileName: String, result: Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+: usar MediaStore API
                val contentValues = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(MediaStore.Images.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
                    put(MediaStore.Images.Media.DATE_MODIFIED, System.currentTimeMillis() / 1000)
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/$albumName")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                
                val resolver = context.contentResolver
                val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { output ->
                        output.write(imageBytes)
                    }
                    
                    contentValues.clear()
                    contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
                    resolver.update(uri, contentValues, null, null)
                    
                    result.success(true)
                } else {
                    result.error("SAVE_FAILED", "No se pudo crear la entrada en MediaStore", null)
                }
            } else {
                // Android < 10: usar el método tradicional de guardar en archivos
                val pictures = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                val albumDir = File(pictures, albumName)
                
                if (!albumDir.exists()) {
                    albumDir.mkdirs()
                }
                
                val file = File(albumDir, fileName)
                FileOutputStream(file).use { output ->
                    output.write(imageBytes)
                }
                
                // Notificar al escáner de medios
                MediaScannerConnection.scanFile(
                    context,
                    arrayOf(file.absolutePath),
                    arrayOf("image/jpeg"),
                    null
                )
                
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("SAVE_FAILED", "Error al guardar imagen: ${e.message}", null)
        }
    }
}