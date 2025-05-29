import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../widgets/scan_button.dart';
import 'camera_screen.dart';
import 'edit_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/document_detector.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // En lugar de usar un método asíncrono que regrese un futuro,
  // lo dividimos en dos métodos: uno que inicia la operación asíncrona
  // y otro que maneja el resultado sin un Future
  void _requestCameraPermission() {
    Permission.camera.request().then((status) {
      if (!mounted) return;
      
      if (status.isGranted) {
        _openCamera();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se necesita permiso de cámara para escanear documentos'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  void _openCamera() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );
  }

  // Similar al método anterior, usamos un enfoque que evita el problema de BuildContext
  void _pickImageFromGallery() {
    final picker = ImagePicker();
    picker.pickImage(source: ImageSource.gallery).then((pickedFile) {
      if (!mounted) return;
      
      if (pickedFile != null) {
        // Mostrar indicador de carga
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Procesando documento...'),
            duration: Duration(seconds: 2),
          ),
        );
        
        _processPickedImage(File(pickedFile.path));
      }
    });
  }
  
  // Método separado para procesar la imagen después de seleccionarla
  void _processPickedImage(File originalImage) {
    DocumentDetector.detectAndCropDocument(originalImage).then((processedImage) {
      if (!mounted) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditScreen(imageFile: processedImage ?? originalImage),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doc Scanner'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/scanner_icon.png',
              width: 120,
              height: 120,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.document_scanner,
                  size: 120,
                  color: Colors.indigo,
                );
              },
            ),
            const SizedBox(height: 40),
            ScanButton(
              icon: Icons.camera_alt,
              label: 'Escanear documento',
              onPressed: _requestCameraPermission,
            ),
            const SizedBox(height: 20),
            ScanButton(
              icon: Icons.photo_library,
              label: 'Seleccionar de galería',
              isSecondary: true,
              onPressed: _pickImageFromGallery,
            ),
          ],
        ),
      ),
    );
  }
}