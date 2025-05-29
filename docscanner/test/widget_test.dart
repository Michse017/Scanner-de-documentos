import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:docscanner/main.dart';
import 'package:docscanner/providers/scanner_provider.dart';
import 'package:docscanner/utils/document_detector.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Configurar directorios temporales para pruebas
  late Directory tempDir;
  late File testImageFile;
  // Definimos resultPath como variable global para compartir entre pruebas
  late String resultPath;
  
  setUpAll(() async {
    // Crear directorios temporales para las pruebas
    tempDir = await Directory.systemTemp.createTemp('test_scanner_');
    
    // Cargar imagen de prueba desde assets
    final ByteData imageData = await rootBundle.load('assets/images/image.jpeg');
    testImageFile = File('${tempDir.path}/test_image.jpg');
    await testImageFile.writeAsBytes(imageData.buffer.asUint8List());
    
    // Definir resultPath aquí para que esté disponible en todas las pruebas
    resultPath = '${tempDir.path}/detected_document.jpg';
  });

  tearDownAll(() async {
    // Limpiar directorios temporales
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('App se inicia correctamente', (WidgetTester tester) async {
    // Construir nuestra app y disparar un frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ScannerProvider()),
        ],
        child: const MyApp(),
      ),
    );

    // Verificar que tenemos el título de la app
    expect(find.text('Doc Scanner'), findsOneWidget);
    
    // Verificar que los botones principales están presentes
    expect(find.text('Escanear documento'), findsOneWidget);
    expect(find.text('Seleccionar de galería'), findsOneWidget);
    
    // Verificar que los iconos están presentes
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    expect(find.byIcon(Icons.photo_library), findsOneWidget);
  });
  
  test('DocumentDetector detecta bordes y aplana correctamente', () async {
    // Verificar que la imagen de prueba existe
    expect(testImageFile.existsSync(), isTrue);
    
    // Detectar y recortar documento usando DocumentDetector
    final File? processedFile = await DocumentDetector.detectAndCropDocument(testImageFile);
    
    // Verificar que el proceso no falló
    expect(processedFile, isNotNull);
    expect(processedFile!.existsSync(), isTrue);
    
    // Decodificar imagen original y procesada para comparación
    final Uint8List originalBytes = await testImageFile.readAsBytes();
    final Uint8List processedBytes = await processedFile.readAsBytes();
    
    final img.Image? originalImage = img.decodeImage(originalBytes);
    final img.Image? processedImage = img.decodeImage(processedBytes);
    
    // Verificar que ambas imágenes se decodificaron correctamente
    expect(originalImage, isNotNull);
    expect(processedImage, isNotNull);
    
    // La imagen procesada debería tener dimensiones proporcionales al documento
    // y diferentes de la original si se detectaron bordes correctamente
    expect(processedImage!.width != originalImage!.width || 
           processedImage.height != originalImage.height, isTrue);
    
    // CORRECCIÓN: Convertir List<int> a Uint8List antes de pasarlo a writeAsBytes
    await File(resultPath).writeAsBytes(
      Uint8List.fromList(img.encodeJpg(processedImage))
    );
    
    debugPrint('Imagen con bordes detectados guardada en: $resultPath');
  });
  
  test('ScannerProvider aplica filtros y guarda correctamente', () async {
    // Inicializar provider
    final provider = ScannerProvider();
    
    // Establecer la imagen original
    await provider.setOriginalImage(testImageFile);
    
    // Verificar que la imagen se cargó correctamente
    expect(provider.originalImage, isNotNull);
    expect(provider.processedImage, isNotNull);
    
    // Probar filtro blanco y negro
    provider.setBlackAndWhite(true);
    expect(provider.blackAndWhite, true);
    
    // Aumentar contraste
    provider.setContrast(40);
    expect(provider.contrast, 40);
    
    // Esperar a que termine el procesamiento
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Verificar que la imagen procesada existe y es diferente a la original
    expect(provider.processedImage, isNotNull);
    expect(provider.processedImage!.path != provider.originalImage!.path, isTrue);
    
    // Guardar versión blanco y negro para inspección visual
    final String bwPath = '${tempDir.path}/blackwhite_document.jpg';
    final Uint8List bwBytes = await provider.processedImage!.readAsBytes();
    await File(bwPath).writeAsBytes(bwBytes);
    
    debugPrint('Imagen en blanco y negro guardada en: $bwPath');
    
    // Restablecer a color y probar otros ajustes
    provider.resetFilters();
    expect(provider.blackAndWhite, false);
    
    // Ajustar contraste y suavizado
    provider.setContrast(20);
    provider.setBlurRadius(1.0);
    
    // Esperar a que termine el procesamiento
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Guardar versión a color para inspección visual
    final String colorPath = '${tempDir.path}/color_document.jpg';
    final Uint8List colorBytes = await provider.processedImage!.readAsBytes();
    await File(colorPath).writeAsBytes(colorBytes);
    
    debugPrint('Imagen a color con filtros guardada en: $colorPath');
    
    // Verificar que ambos archivos existen y tienen contenido
    final File bwFile = File(bwPath);
    final File colorFile = File(colorPath);
    
    expect(bwFile.existsSync(), isTrue);
    expect(colorFile.existsSync(), isTrue);
    
    // Verificar que tienen tamaños diferentes (indica procesamiento diferente)
    final int bwSize = await bwFile.length();
    final int colorSize = await colorFile.length();
    
    expect(bwSize > 0, isTrue);
    expect(colorSize > 0, isTrue);
    expect(bwSize != colorSize, isTrue);
    
    // Crear directorio de salida si no existe
    final outputDir = Directory('${Directory.current.path}/assets/output');
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }
    
    await bwFile.copy('${outputDir.path}/test_blackwhite.jpg');
    await colorFile.copy('${outputDir.path}/test_color.jpg');
    await File(resultPath).copy('${outputDir.path}/test_detected.jpg');
    
    debugPrint('Resultados copiados a: ${outputDir.path}');
  });
}