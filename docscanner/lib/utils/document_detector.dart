import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Color;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class DocumentDetector {
  static Future<File?> detectAndCropDocument(File imageFile) async {
    try {
      // Cargar la imagen
      Uint8List imageBytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) return null;

      // Redimensionar imagen si es muy grande para procesamiento más rápido
      img.Image processImage = originalImage;
      if (originalImage.width > 1000 || originalImage.height > 1000) {
        processImage = img.copyResize(
          originalImage,
          width: originalImage.width > originalImage.height ? 1000 : null,
          height: originalImage.width <= originalImage.height ? 1000 : null,
          interpolation: img.Interpolation.cubic,
        );
      }

      // Convertir a escala de grises para procesamiento
      img.Image grayscale = img.grayscale(processImage);

      // Ajustar contraste y brillo para mejorar detección de bordes
      grayscale = img.adjustColor(
        grayscale,
        contrast: 1.5,
        brightness: 0.1,
      );

      // Detectar bordes
      img.Image edged = _detectEdges(grayscale);

      // Encontrar esquinas del documento
      List<Point<int>> docCorners = _findDocumentCorners(edged);

      // Transformar perspectiva si se hallan 4 esquinas
      if (docCorners.length == 4) {
        // Escalar esquinas de vuelta al tamaño original (si se usó versión reducida)
        if (processImage != originalImage) {
          double scaleX = originalImage.width / processImage.width;
          double scaleY = originalImage.height / processImage.height;
          docCorners = docCorners.map((point) => 
            Point((point.x * scaleX).toInt(), (point.y * scaleY).toInt())
          ).toList();
        }

        // Ordenar esquinas
        docCorners = _orderPoints(docCorners);

        // Determinar ancho y alto deseados
        double width = max(
          _distance(docCorners[0], docCorners[1]),
          _distance(docCorners[2], docCorners[3]),
        );
        double height = max(
          _distance(docCorners[0], docCorners[3]),
          _distance(docCorners[1], docCorners[2]),
        );

        final int docWidth = width.toInt();
        final int docHeight = height.toInt();

        // Transformación de perspectiva
        img.Image warpedImage = _warpPerspective(
          originalImage,
          docCorners,
          docWidth,
          docHeight,
        );

        // Guardar resultado
        final tmpDir = await getTemporaryDirectory();
        final outputPath =
            '${tmpDir.path}/doc_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        File outputFile = File(outputPath);
        await outputFile.writeAsBytes(img.encodeJpg(warpedImage, quality: 95));
        
        // También guardar para depuración
        final debugOutputPath = 'assets/output/detected_document.jpg';
        final debugDir = Directory('assets/output');
        if (!debugDir.existsSync()) {
          debugDir.createSync(recursive: true);
        }
        await File(debugOutputPath).writeAsBytes(img.encodeJpg(warpedImage, quality: 95));
        
        return outputFile;
      } else {
        // Si no se detecta un contorno confiable, aplicar solo mejoras básicas
        return await _enhanceImage(originalImage, imageFile);
      }
    } catch (e) {
      debugPrint('Error en detección de documento: $e');
      return imageFile; // Devuelve original ante error
    }
  }

  // Detector de bordes con Sobel + operaciones morfológicas manuales
  static img.Image _detectEdges(img.Image grayscale) {
    // Reducir ruido con blur
    img.Image blurred = img.gaussianBlur(grayscale, radius: 2);

    // Crear lienzo para los bordes
    img.Image edges = img.Image(width: blurred.width, height: blurred.height);

    // Operador Sobel manual
    for (int y = 1; y < blurred.height - 1; y++) {
      for (int x = 1; x < blurred.width - 1; x++) {
        int tl = blurred.getPixel(x - 1, y - 1).luminance.toInt();
        int t = blurred.getPixel(x, y - 1).luminance.toInt();
        int tr = blurred.getPixel(x + 1, y - 1).luminance.toInt();
        int l = blurred.getPixel(x - 1, y).luminance.toInt();
        int r = blurred.getPixel(x + 1, y).luminance.toInt();
        int bl = blurred.getPixel(x - 1, y + 1).luminance.toInt();
        int b = blurred.getPixel(x, y + 1).luminance.toInt();
        int br = blurred.getPixel(x + 1, y + 1).luminance.toInt();

        int gx = (tr + 2 * r + br) - (tl + 2 * l + bl);
        int gy = (bl + 2 * b + br) - (tl + 2 * t + tr);

        int mag = sqrt(gx * gx + gy * gy).toInt();
        img.Color color = mag > 40 
          ? img.ColorRgb8(255, 255, 255) // blanco para bordes
          : img.ColorRgb8(0, 0, 0); // negro para no bordes

        edges.setPixel(x, y, color);
      }
    }

    // Implementar dilation y erosion manualmente
    edges = _manualDilation(edges, 1);
    edges = _manualErosion(edges, 1);

    return edges;
  }

  // Implementación manual de dilation
  static img.Image _manualDilation(img.Image image, int radius) {
    img.Image result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        bool isWhite = false;
        
        // Buscar cualquier pixel blanco en el vecindario
        for (int dy = -radius; dy <= radius && !isWhite; dy++) {
          for (int dx = -radius; dx <= radius && !isWhite; dx++) {
            int nx = x + dx;
            int ny = y + dy;
            
            if (nx >= 0 && nx < image.width && ny >= 0 && ny < image.height) {
              // Si hay un pixel blanco en el vecindario, el resultado es blanco
              if (image.getPixel(nx, ny).r > 200) {
                isWhite = true;
              }
            }
          }
        }
        
        result.setPixel(x, y, isWhite 
          ? img.ColorRgb8(255, 255, 255) 
          : img.ColorRgb8(0, 0, 0));
      }
    }
    
    return result;
  }

  // Implementación manual de erosion
  static img.Image _manualErosion(img.Image image, int radius) {
    img.Image result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        bool allWhite = true;
        
        // Verificar si todos los pixeles en el vecindario son blancos
        for (int dy = -radius; dy <= radius && allWhite; dy++) {
          for (int dx = -radius; dx <= radius && allWhite; dx++) {
            int nx = x + dx;
            int ny = y + dy;
            
            if (nx >= 0 && nx < image.width && ny >= 0 && ny < image.height) {
              // Si hay un pixel negro en el vecindario, el resultado es negro
              if (image.getPixel(nx, ny).r < 200) {
                allWhite = false;
              }
            }
          }
        }
        
        result.setPixel(x, y, allWhite 
          ? img.ColorRgb8(255, 255, 255) 
          : img.ColorRgb8(0, 0, 0));
      }
    }
    
    return result;
  }

  // Buscar esquinas en la imagen de bordes
  static List<Point<int>> _findDocumentCorners(img.Image edgedImage) {
    int width = edgedImage.width;
    int height = edgedImage.height;

    Point<int> topLeft = Point(width, height);
    Point<int> topRight = Point(0, height);
    Point<int> bottomRight = Point(0, 0);
    Point<int> bottomLeft = Point(width, 0);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        var pixel = edgedImage.getPixel(x, y);
        if (pixel.luminance > 200) {
          // Buscar puntos extremos
          if (x + y < topLeft.x + topLeft.y) topLeft = Point(x, y);
          if (x - y > topRight.x - topRight.y) topRight = Point(x, y);
          if (x + y > bottomRight.x + bottomRight.y) bottomRight = Point(x, y);
          if (y - x > bottomLeft.y - bottomLeft.x) bottomLeft = Point(x, y);
        }
      }
    }

    bool edgeCase = false;
    if (_isNearEdge(topLeft, width, height) ||
        _isNearEdge(topRight, width, height) ||
        _isNearEdge(bottomRight, width, height) ||
        _isNearEdge(bottomLeft, width, height)) {
      edgeCase = true;
    }

    if (edgeCase) {
      int marginX = (width * 0.05).toInt();
      int marginY = (height * 0.05).toInt();
      return [
        Point(marginX, marginY),
        Point(width - marginX, marginY),
        Point(width - marginX, height - marginY),
        Point(marginX, height - marginY),
      ];
    }

    int expandX = (width * 0.02).toInt();
    int expandY = (height * 0.02).toInt();

    topLeft = Point(
      max(0, topLeft.x - expandX),
      max(0, topLeft.y - expandY),
    );
    topRight = Point(
      min(width - 1, topRight.x + expandX),
      max(0, topRight.y - expandY),
    );
    bottomRight = Point(
      min(width - 1, bottomRight.x + expandX),
      min(height - 1, bottomRight.y + expandY),
    );
    bottomLeft = Point(
      max(0, bottomLeft.x - expandX),
      min(height - 1, bottomLeft.y + expandY),
    );

    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  static bool _isNearEdge(Point<int> point, int width, int height) {
    int threshold = (width * 0.03).toInt();
    return (point.x < threshold ||
        point.x > width - threshold ||
        point.y < threshold ||
        point.y > height - threshold);
  }

  static List<Point<int>> _orderPoints(List<Point<int>> points) {
    if (points.length != 4) return points;
    int centerX = (points.fold(0, (sum, p) => sum + p.x) ~/ points.length);
    int centerY = (points.fold(0, (sum, p) => sum + p.y) ~/ points.length);

    // Fixed: Use List.generate instead of List.filled with a mutable default value
    List<Point<int>> orderedPoints = List.generate(4, (_) => const Point(0, 0));
    for (Point<int> point in points) {
      int index = ((point.y < centerY) ? 0 : 2) + ((point.x > centerX) ? 1 : 0);
      orderedPoints[index] = point;
    }
    return orderedPoints;
  }

  static double _distance(Point<int> p1, Point<int> p2) {
    double dx = (p2.x - p1.x).toDouble();
    double dy = (p2.y - p1.y).toDouble();
    return sqrt(dx * dx + dy * dy);
  }

  static img.Image _warpPerspective(
    img.Image src,
    List<Point<int>> corners,
    int targetWidth,
    int targetHeight,
  ) {
    img.Image dest = img.Image(width: targetWidth, height: targetHeight);

    List<double> srcPoints = [
      corners[0].x.toDouble(),
      corners[0].y.toDouble(),
      corners[1].x.toDouble(),
      corners[1].y.toDouble(),
      corners[2].x.toDouble(),
      corners[2].y.toDouble(),
      corners[3].x.toDouble(),
      corners[3].y.toDouble()
    ];

    List<double> dstPoints = [
      0.0,
      0.0,
      targetWidth.toDouble(),
      0.0,
      targetWidth.toDouble(),
      targetHeight.toDouble(),
      0.0,
      targetHeight.toDouble()
    ];

    List<double> perspMatrix = _getPerspectiveTransform(srcPoints, dstPoints);

    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        double w = perspMatrix[6] * x + perspMatrix[7] * y + perspMatrix[8];
        double srcX =
            (perspMatrix[0] * x + perspMatrix[1] * y + perspMatrix[2]) / w;
        double srcY =
            (perspMatrix[3] * x + perspMatrix[4] * y + perspMatrix[5]) / w;

        if (srcX >= 0 && srcX < src.width && srcY >= 0 && srcY < src.height) {
          // Usar interpolación bilineal para mejor calidad
          dest.setPixel(x, y, _bilinearInterpolate(src, srcX, srcY));
        }
      }
    }
    return dest;
  }

  static Future<File> _enhanceImage(img.Image image, File originalFile) async {
    int marginX = (image.width * 0.02).toInt();
    int marginY = (image.height * 0.02).toInt();

    img.Image cropped = img.copyCrop(
      image,
      x: marginX,
      y: marginY,
      width: image.width - (marginX * 2),
      height: image.height - (marginY * 2),
    );

    img.Image enhanced = img.adjustColor(
      cropped,
      contrast: 1.2,
      brightness: 0.05,
      saturation: 1.1,
    );

    final tmpDir = await getTemporaryDirectory();
    final outputPath =
        '${tmpDir.path}/doc_enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
    File outputFile = File(outputPath);
    await outputFile.writeAsBytes(img.encodeJpg(enhanced, quality: 95));
    return outputFile;
  }

  static img.Color _bilinearInterpolate(img.Image image, double x, double y) {
    int x0 = x.floor();
    int y0 = y.floor();
    int x1 = min(x0 + 1, image.width - 1);
    int y1 = min(y0 + 1, image.height - 1);

    double dx = x - x0;
    double dy = y - y0;

    var tlPixel = image.getPixel(x0, y0);
    var trPixel = image.getPixel(x1, y0);
    var blPixel = image.getPixel(x0, y1);
    var brPixel = image.getPixel(x1, y1);

    int r = _interpolate(
      tlPixel.r.toInt(),
      trPixel.r.toInt(),
      blPixel.r.toInt(),
      brPixel.r.toInt(),
      dx,
      dy,
    );
    int g = _interpolate(
      tlPixel.g.toInt(),
      trPixel.g.toInt(),
      blPixel.g.toInt(),
      brPixel.g.toInt(),
      dx,
      dy,
    );
    int b = _interpolate(
      tlPixel.b.toInt(),
      trPixel.b.toInt(),
      blPixel.b.toInt(),
      brPixel.b.toInt(),
      dx,
      dy,
    );

    return img.ColorRgb8(r, g, b);
  }

  static int _interpolate(
    int tl,
    int tr,
    int bl,
    int br,
    double dx,
    double dy,
  ) {
    double top = tl * (1 - dx) + tr * dx;
    double bottom = bl * (1 - dx) + br * dx;
    return (top * (1 - dy) + bottom * dy).toInt().clamp(0, 255);
  }

  static List<double> _getPerspectiveTransform(
    List<double> src,
    List<double> dst,
  ) {
    List<double> matrix = List<double>.filled(9, 0);
    List<List<double>> A =
        List<List<double>>.generate(8, (_) => List<double>.filled(8, 0));
    List<double> B = List<double>.filled(8, 0);

    for (int i = 0; i < 4; i++) {
      int srcIdx = i * 2;
      int dstIdx = i * 2;

      double srcX = src[srcIdx];
      double srcY = src[srcIdx + 1];
      double dstX = dst[dstIdx];
      double dstY = dst[dstIdx + 1];

      A[i][0] = srcX;
      A[i][1] = srcY;
      A[i][2] = 1;
      A[i][6] = -dstX * srcX;
      A[i][7] = -dstX * srcY;
      B[i] = dstX;

      A[i + 4][3] = srcX;
      A[i + 4][4] = srcY;
      A[i + 4][5] = 1;
      A[i + 4][6] = -dstY * srcX;
      A[i + 4][7] = -dstY * srcY;
      B[i + 4] = dstY;
    }

    List<double> x = _solveLinearSystem(A, B);
    for (int i = 0; i < 8; i++) {
      matrix[i] = x[i];
    }
    matrix[8] = 1.0;
    return matrix;
  }

  static List<double> _solveLinearSystem(List<List<double>> A, List<double> b) {
    int n = b.length;
    List<double> x = List<double>.filled(n, 0);

    for (int i = 0; i < n; i++) {
      int maxRow = i;
      double maxVal = A[i][i].abs();
      for (int k = i + 1; k < n; k++) {
        if (A[k][i].abs() > maxVal) {
          maxVal = A[k][i].abs();
          maxRow = k;
        }
      }
      if (maxRow != i) {
        for (int k = i; k < n; k++) {
          double tmp = A[i][k];
          A[i][k] = A[maxRow][k];
          A[maxRow][k] = tmp;
        }
        double tempB = b[i];
        b[i] = b[maxRow];
        b[maxRow] = tempB;
      }
      for (int k = i + 1; k < n; k++) {
        double factor = A[k][i] / A[i][i];
        b[k] -= factor * b[i];
        for (int j = i; j < n; j++) {
          A[k][j] -= factor * A[i][j];
        }
      }
    }
    for (int i = n - 1; i >= 0; i--) {
      x[i] = b[i];
      for (int j = i + 1; j < n; j++) {
        x[i] -= A[i][j] * x[j];
      }
      x[i] /= A[i][i];
    }
    return x;
  }
}