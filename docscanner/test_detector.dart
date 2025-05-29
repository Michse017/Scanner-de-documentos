import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

Future<void> main() async {
  // Probar los filtros en una imagen de prueba
  print("Probando filtros...");
  
  // Asegurar que el directorio de salida existe
  Directory outputDir = Directory('assets/output/filters');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }
  
  // Cargar la imagen de prueba
  final File imageFile = File('assets/images/image.jpeg');
  if (!imageFile.existsSync()) {
    print("Error: No se encuentra la imagen de prueba");
    return;
  }
  
  print("Cargando imagen: ${imageFile.path}");
  final bytes = await imageFile.readAsBytes();
  final img.Image? originalImage = img.decodeImage(bytes);
  
  if (originalImage == null) {
    print("Error: No se pudo decodificar la imagen");
    return;
  }
  
  // Guardar original
  await File('assets/output/filters/original.jpg')
      .writeAsBytes(img.encodeJpg(originalImage, quality: 95));
  
  // Probar blanco y negro
  print("Aplicando filtro blanco y negro...");
  final bwImage = img.grayscale(originalImage);
  await File('assets/output/filters/bw.jpg')
      .writeAsBytes(img.encodeJpg(bwImage, quality: 95));
  
  // Probar contraste alto
  print("Aplicando alto contraste...");
  final highContrastImage = img.adjustColor(
    originalImage.clone(),
    contrast: 1.5,
  );
  await File('assets/output/filters/high_contrast.jpg')
      .writeAsBytes(img.encodeJpg(highContrastImage, quality: 95));
  
  // Probar contraste bajo
  print("Aplicando bajo contraste...");
  final lowContrastImage = img.adjustColor(
    originalImage.clone(),
    contrast: 0.5,
  );
  await File('assets/output/filters/low_contrast.jpg')
      .writeAsBytes(img.encodeJpg(lowContrastImage, quality: 95));
  
  // Probar desenfoque
  print("Aplicando desenfoque...");
  final blurImage = img.gaussianBlur(originalImage.clone(), radius: 3);
  await File('assets/output/filters/blur.jpg')
      .writeAsBytes(img.encodeJpg(blurImage, quality: 95));
  
  // Probar combinación de filtros
  print("Aplicando combinación de filtros...");
  var combinedImage = img.grayscale(originalImage.clone());
  combinedImage = img.adjustColor(combinedImage, contrast: 1.3);
  combinedImage = img.gaussianBlur(combinedImage, radius: 1);
  await File('assets/output/filters/combined.jpg')
      .writeAsBytes(img.encodeJpg(combinedImage, quality: 95));
  
  print("Pruebas de filtros completadas. Resultados en assets/output/filters/");
}