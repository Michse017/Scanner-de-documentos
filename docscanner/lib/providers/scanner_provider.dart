import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Color; // Ocultar Color de Flutter
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Proveedor para manejar el procesamiento de imágenes escaneadas
/// con filtros y efectos aplicables en tiempo real
class ScannerProvider with ChangeNotifier {
  File? _originalImage;
  File? _processedImage;
  bool _processingImage = false;
  
  // Parámetros de filtros
  bool _blackAndWhite = false;
  int _contrast = 0;
  double _blurRadius = 0.0;
  
  // Caché de imágenes procesadas
  final Map<String, img.Image> _imageCache = {};
  img.Image? _lastOriginal;

  // Getters
  File? get originalImage => _originalImage;
  File? get processedImage => _processedImage;
  bool get processingImage => _processingImage;
  bool get blackAndWhite => _blackAndWhite;
  int get contrast => _contrast;
  double get blurRadius => _blurRadius;

  /// Establece la imagen original y aplica el procesamiento inicial
  Future<void> setOriginalImage(File imageFile) async {
    if (!imageFile.existsSync()) {
      debugPrint('Advertencia: El archivo de imagen no existe');
      return;
    }

    _originalImage = imageFile;
    _processedImage = imageFile;
    _imageCache.clear(); // Limpiar caché al cambiar de imagen
    
    // Decodificar y guardar la imagen original en memoria
    try {
      Uint8List bytes = await imageFile.readAsBytes();
      _lastOriginal = img.decodeImage(bytes);
    } catch (e) {
      debugPrint('Error decodificando imagen original: $e');
    }
    
    notifyListeners();
    
    // Aplicar procesamiento inicial
    await _processImage();
  }

  /// Restablece todos los filtros a sus valores predeterminados
  void resetFilters() {
    _blackAndWhite = false;
    _contrast = 0;
    _blurRadius = 0.0;
    
    if (_originalImage != null) {
      _processImage();
    }
  }

  /// Activa/desactiva el filtro de blanco y negro
  void setBlackAndWhite(bool value) {
    if (_blackAndWhite == value) return; // Evitar procesamiento innecesario
    _blackAndWhite = value;
    _processImage();
  }

  /// Ajusta el nivel de contraste (-100 a 100)
  void setContrast(int value) {
    // Asegurar que el valor está en el rango correcto
    int clampedValue = value.clamp(-100, 100);
    if (_contrast == clampedValue) return; // Evitar procesamiento innecesario
    _contrast = clampedValue;
    _processImage();
  }

  /// Ajusta el nivel de desenfoque/suavizado (0 a 5)
  void setBlurRadius(double value) {
    // Asegurar que el valor está en el rango correcto
    double clampedValue = value.clamp(0.0, 5.0);
    if (_blurRadius == clampedValue) return; // Evitar procesamiento innecesario
    _blurRadius = clampedValue;
    _processImage();
  }

  /// Procesa la imagen aplicando los filtros actuales
  Future<void> _processImage() async {
    if (_originalImage == null) return;

    _processingImage = true;
    notifyListeners();

    try {
      // Procesar la imagen utilizando los filtros configurados
      final resultFile = await _applyFilters(_originalImage!);
      _processedImage = resultFile;
    } catch (e) {
      debugPrint('Error al procesar la imagen: $e');
      // En caso de error, mantener la imagen original
      _processedImage = _originalImage;
    }

    _processingImage = false;
    notifyListeners();
  }

  /// Aplica los filtros configurados a la imagen original
  Future<File> _applyFilters(File imageFile) async {
    // Crear clave para caché basada en configuración actual
    // Corregido: Eliminadas llaves innecesarias en la interpolación
    String cacheKey = '${_blackAndWhite}_${_contrast}_$_blurRadius';
    
    // Verificar caché
    img.Image? processedImage = _imageCache[cacheKey];
    
    if (processedImage == null) {
      // No en caché, procesar
      img.Image? image;
      
      // Usar la imagen ya decodificada si está disponible
      if (_lastOriginal != null) {
        image = _lastOriginal!.clone();
      } else {
        // Cargar imagen desde archivo
        Uint8List imageBytes = await imageFile.readAsBytes();
        image = img.decodeImage(imageBytes);
        
        if (image != null) {
          // Guardar para uso futuro
          _lastOriginal = image.clone();
        }
      }
      
      if (image == null) {
        throw Exception('No se pudo decodificar la imagen');
      }

      // Aplicar filtros
      
      // 1. Primero aplicar escala de grises si está activado
      if (_blackAndWhite) {
        image = img.grayscale(image);
      }
      
      // 2. Luego el contraste
      if (_contrast != 0) {
        // Calcular factor de contraste (1.0 es neutro)
        double contrastFactor = 1 + _contrast / 100;
        
        if (_blackAndWhite) {
          // Para imágenes B&N, aplicar umbralización adaptativa si es alto contraste
          if (_contrast > 30) {
            image = _adaptiveThreshold(image, 11, _contrast / 10);
          } else {
            image = img.adjustColor(
              image,
              contrast: contrastFactor,
              brightness: _contrast > 0 ? 0.05 : -0.05,
            );
          }
        } else {
          // Para imágenes a color
          image = img.adjustColor(
            image,
            contrast: contrastFactor,
          );
        }
      }
      
      // 3. Por último el desenfoque (si está activado)
      if (_blurRadius > 0) {
        image = img.gaussianBlur(image, radius: _blurRadius.toInt());
      }
      
      // Guardar en caché
      _imageCache[cacheKey] = image;
      processedImage = image;
    }

    // Guardar imagen procesada en archivo temporal
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final File resultFile = File(tempPath);
    
    // Guardar con buena calidad para evitar degradación visible
    await resultFile.writeAsBytes(img.encodeJpg(processedImage, quality: 95));
    
    return resultFile;
  }
  
  /// Umbralización adaptativa para documentos B&N de alto contraste
  img.Image _adaptiveThreshold(img.Image src, int blockSize, double c) {
    img.Image result = img.Image(width: src.width, height: src.height);
    
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        // Calcular la media local
        int sum = 0;
        int count = 0;
        
        for (int dy = -blockSize ~/ 2; dy <= blockSize ~/ 2; dy++) {
          for (int dx = -blockSize ~/ 2; dx <= blockSize ~/ 2; dx++) {
            int nx = x + dx;
            int ny = y + dy;
            
            if (nx >= 0 && nx < src.width && ny >= 0 && ny < src.height) {
              // Corrección: Obtener valor de luminancia del objeto Pixel
              sum += src.getPixel(nx, ny).luminance.toInt();
              count++;
            }
          }
        }
        
        double mean = sum / count;
        // Corrección: Obtener valor de luminancia del objeto Pixel en lugar de usar &
        int pixelValue = src.getPixel(x, y).luminance.toInt();
        
        // Aplicar umbral local
        if (pixelValue > mean - c) {
          // Corrección: Usar ColorRgb8 de la librería image en lugar de Color de Flutter
          result.setPixel(x, y, img.ColorRgb8(255, 255, 255)); // Blanco
        } else {
          // Corrección: Usar ColorRgb8 de la librería image en lugar de Color de Flutter
          result.setPixel(x, y, img.ColorRgb8(0, 0, 0)); // Negro
        }
      }
    }
    
    return result;
  }
  
  @override
  void dispose() {
    // Limpiar archivos temporales y caché
    _cleanupTempFiles();
    _imageCache.clear();
    _lastOriginal = null;
    super.dispose();
  }
  
  /// Limpia archivos temporales generados durante el procesamiento
  Future<void> _cleanupTempFiles() async {
    try {
      if (_processedImage != null && 
          _originalImage != null && 
          _processedImage!.path != _originalImage!.path &&
          _processedImage!.existsSync()) {
        await _processedImage!.delete();
      }
    } catch (e) {
      debugPrint('Error al limpiar archivos temporales: $e');
    }
  }
}