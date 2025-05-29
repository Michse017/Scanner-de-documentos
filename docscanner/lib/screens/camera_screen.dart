import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import '../utils/document_detector.dart';
import 'edit_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _processingImage = false;
  bool _hasPermissions = false;
  bool _flashEnabled = false;
  String? _errorMessage;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionsAndInitCamera();
  }
  
  @override
  void dispose() {
    _controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Manejar cambios en el ciclo de vida para reiniciar la cámara cuando sea necesario
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(_selectedCameraIndex);
    }
  }

  // Verificar permisos y inicializar la cámara
  Future<void> _checkPermissionsAndInitCamera() async {
    final status = await Permission.camera.request();
    
    if (!mounted) return;
    
    setState(() {
      _hasPermissions = status.isGranted;
      _errorMessage = status.isGranted ? null : 'Se requieren permisos de cámara';
    });
    
    if (status.isGranted) {
      await _initializeCamera(0);
    }
  }

  // Inicializar la cámara con un índice específico
  Future<void> _initializeCamera(int cameraIndex) async {
    if (!mounted) return;
    
    setState(() {
      _errorMessage = null;
    });
    
    try {
      _cameras = await availableCameras();
      
      if (!mounted) return;
      
      if (_cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No se detectaron cámaras en el dispositivo';
        });
        return;
      }
      
      if (cameraIndex >= _cameras.length) {
        cameraIndex = 0;
      }
      
      // Liberar el controlador anterior si existe
      await _controller?.dispose();
      
      // Crear nuevo controlador
      _controller = CameraController(
        _cameras[cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      // Inicializar el controlador
      await _controller!.initialize();
      
      if (!mounted) return;
      
      // Ajustar la exposición para mejor calidad
      await _controller!.setExposureMode(ExposureMode.auto);
      await _controller!.setFocusMode(FocusMode.auto);
      
      _selectedCameraIndex = cameraIndex;
      
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _errorMessage = 'Error al inicializar la cámara: $e';
        _isCameraInitialized = false;
      });
    }
  }

  // Cambiar entre cámaras frontal y trasera
  Future<void> _switchCamera() async {
    if (_cameras.isEmpty || _processingImage) return;
    
    final newIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initializeCamera(newIndex);
  }
  
  // Activar/desactivar flash
  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized || _processingImage) return;
    
    try {
      final newFlashMode = _flashEnabled ? FlashMode.off : FlashMode.torch;
      await _controller!.setFlashMode(newFlashMode);
      
      if (!mounted) return;
      
      setState(() {
        _flashEnabled = !_flashEnabled;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _errorMessage = 'Error al cambiar flash: $e';
      });
    }
  }

  // Tomar foto y procesarla
  Future<void> _takePicture() async {
    if (_controller == null || 
        !_controller!.value.isInitialized || 
        _processingImage) {
      return;
    }

    setState(() {
      _processingImage = true;
      _errorMessage = null;
    });

    try {
      final XFile photo = await _controller!.takePicture();
      final originalImage = File(photo.path);
      
      if (!mounted) {
        // Si el widget ya no está montado, limpiar recursos y salir
        try { await File(photo.path).delete(); } catch (_) {}
        return;
      }
      
      // Capturar el contexto antes del gap asíncrono
      final scaffoldMessengerContext = ScaffoldMessenger.of(context);
      
      // Mostrar mensaje de procesamiento
      scaffoldMessengerContext.showSnackBar(
        const SnackBar(
          content: Text('Detectando bordes del documento...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // Detectar bordes y corregir la perspectiva usando el detector simplificado
      final processedImage = await DocumentDetector.detectAndCropDocument(originalImage);
      
      // Usar la imagen procesada o la original si falló el procesamiento
      final imageFile = processedImage ?? originalImage;

      // Verificar si el contexto sigue montado
      if (!mounted) return;
      
      // Navegar a la pantalla de edición
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditScreen(imageFile: imageFile),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al tomar la foto: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermissions) {
      return _buildPermissionsScreen();
    }

    if (!_isCameraInitialized) {
      return _buildLoadingScreen();
    }

    return _buildCameraScreen();
  }

  // Widget para la pantalla de permisos
  Widget _buildPermissionsScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Escáner de Documentos')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Se requieren permisos de cámara'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _checkPermissionsAndInitCamera,
              child: const Text('Conceder permisos'),
            )
          ],
        ),
      ),
    );
  }

  // Widget para la pantalla de carga
  Widget _buildLoadingScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Escáner de Documentos')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_errorMessage ?? 'Inicializando cámara...'),
          ],
        ),
      ),
    );
  }

  // Widget para la pantalla de la cámara
  Widget _buildCameraScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capturar Documento'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          // Botón para flash
          IconButton(
            icon: Icon(_flashEnabled ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleFlash,
          ),
          // Botón para cambiar cámara
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Vista previa de la cámara
          SizedBox.expand(
            child: _controller!.buildPreview(),
          ),

          // Guías para alinear el documento
          const Positioned.fill(
            child: CustomPaint(
              painter: DocumentGuidePainter(),
            ),
          ),
          
          // Mensaje de error (si existe)
          if (_errorMessage != null)
            Positioned(
              bottom: 120,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(204), // Equivalente a opacity 0.8
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          
          // Indicador de procesamiento
          if (_processingImage)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Procesando imagen...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          
          // Instrucciones
          const Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black45,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Text(
                  'Alinee el documento dentro del marco',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _processingImage ? null : _takePicture,
        backgroundColor: _processingImage ? Colors.grey : Colors.indigo,
        child: const Icon(
          Icons.camera_alt,
          color: Colors.white,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// Pintor personalizado para las guías de alineación
class DocumentGuidePainter extends CustomPainter {
  const DocumentGuidePainter();
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(128) // Equivalente a opacity 0.5
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    // Línea horizontal central
    canvas.drawLine(
      Offset(0, size.height / 2), 
      Offset(size.width, size.height / 2), 
      paint
    );
    
    // Línea vertical central
    canvas.drawLine(
      Offset(size.width / 2, 0), 
      Offset(size.width / 2, size.height), 
      paint
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}