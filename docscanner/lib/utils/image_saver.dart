import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

/// Clase para guardar imágenes en el almacenamiento del dispositivo
/// adaptada para Android moderno (11+) y con mejor manejo de permisos
class ImageSaver {
  // Channel para comunicarse con código nativo de Android
  static const MethodChannel _channel = MethodChannel('com.example.docscanner/media_scanner');

  /// Guarda una imagen en el almacenamiento del dispositivo y la hace visible en la galería
  static Future<bool> saveImage(File imageFile, {String albumName = "DocScanner"}) async {
    try {
      developer.log('Iniciando guardado de imagen: ${imageFile.path}');
      
      // Verificar que el archivo existe y tiene tamaño
      if (!await imageFile.exists()) {
        developer.log('Error: El archivo no existe');
        return false;
      }
      
      final fileSize = await imageFile.length();
      if (fileSize <= 0) {
        developer.log('Error: El archivo está vacío');
        return false;
      }
      
      // Solicitar permisos según la versión de Android
      final permissionStatus = await _requestPermissions();
      if (!permissionStatus) {
        developer.log('Error: Permisos insuficientes para guardar la imagen');
        return false;
      }
      
      // Guardar la imagen usando el método apropiado para la versión de Android
      if (Platform.isAndroid) {
        return await _saveImageAndroid(imageFile, albumName);
      } else {
        // Para otras plataformas, usar método más simple
        return await _saveImageGeneric(imageFile, albumName);
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error al guardar imagen', 
        error: e, 
        stackTrace: stackTrace
      );
      return false;
    }
  }

  /// Solicita los permisos necesarios para guardar imágenes
  static Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) return true;
    
    try {
      // Para Android, necesitamos permisos de storage
      PermissionStatus status = await Permission.storage.request();
      
      if (status.isGranted) {
        return true;
      }
      
      // Si el permiso básico no es suficiente, intentamos con photos
      status = await Permission.photos.request();
      return status.isGranted;
    } catch (e) {
      developer.log('Error al solicitar permisos: $e');
      return false;
    }
  }

  /// Método optimizado para guardar en Android moderno (10+)
  static Future<bool> _saveImageAndroid(File imageFile, String albumName) async {
    try {
      // El enfoque cambia según la versión de Android
      final String destinationPath = await _getAndroidDestinationPath(albumName);
      if (destinationPath.isEmpty) {
        return false;
      }
      
      // Crear directorio de destino si no existe
      final Directory destinationDir = Directory(destinationPath);
      if (!await destinationDir.exists()) {
        await destinationDir.create(recursive: true);
      }
      
      // Generar nombre de archivo único
      final String fileName = 'doc_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = path.join(destinationPath, fileName);
      
      // Copiar el archivo
      await imageFile.copy(filePath);
      
      // Escanear el archivo para que aparezca en la galería
      try {
        await _channel.invokeMethod('scanFile', {'filePath': filePath});
      } catch (e) {
        // Si falla, usar un enfoque alternativo para notificar
        _triggerMediaScan(filePath);
      }
      
      return true;
    } catch (e) {
      developer.log('Error específico de Android: $e');
      return false;
    }
  }
  
  /// Obtiene la ruta de destino para Android
  static Future<String> _getAndroidDestinationPath(String albumName) async {
    try {
      final List<Directory>? externalDirs = await getExternalStorageDirectories();
      
      if (externalDirs == null || externalDirs.isEmpty) {
        developer.log('No se encontraron directorios de almacenamiento externo');
        return "";
      }
      
      // Intentar encontrar el directorio raíz del almacenamiento externo
      String baseDir = externalDirs.first.path;
      List<String> parts = baseDir.split("/");
      int index = parts.indexOf("Android");
      
      if (index > 0) {
        String rootPath = parts.sublist(0, index).join("/");
        
        // Primero intentamos con DCIM que es más compatible con galería
        String dcimPath = "$rootPath/DCIM/$albumName";
        return dcimPath;
      }
      
      // Fallback: usar el directorio de la app
      final appDir = await getApplicationDocumentsDirectory();
      return "${appDir.path}/Pictures/$albumName";
    } catch (e) {
      developer.log('Error al determinar ruta de destino: $e');
      return "";
    }
  }
  
  /// Método genérico para otras plataformas
  static Future<bool> _saveImageGeneric(File imageFile, String albumName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final saveDir = Directory('${dir.path}/$albumName');
      
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      
      final String fileName = 'doc_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String savePath = path.join(saveDir.path, fileName);
      
      await imageFile.copy(savePath);
      return true;
    } catch (e) {
      developer.log('Error al guardar imagen genérico: $e');
      return false;
    }
  }
  
  /// Método alternativo para notificar sobre nuevos archivos
  static Future<void> _triggerMediaScan(String filePath) async {
    try {
      final File file = File(filePath);
      
      // Crear un archivo temporal y eliminarlo para forzar un escaneo
      final tempFile = File('${path.dirname(filePath)}/.tmp_scan_trigger');
      await tempFile.create();
      await Future.delayed(const Duration(milliseconds: 500));
      await tempFile.delete();
      
      // Actualizar la fecha del archivo para forzar un rescaneo
      await file.setLastModified(DateTime.now());
    } catch (e) {
      developer.log('Error al forzar escaneo de medios: $e');
    }
  }
}