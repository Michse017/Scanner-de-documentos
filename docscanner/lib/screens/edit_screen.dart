import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/scanner_provider.dart';
import '../widgets/processing_option.dart';
import '../utils/image_saver.dart';
import 'package:share_plus/share_plus.dart';

class EditScreen extends StatefulWidget {
  final File imageFile;

  const EditScreen({super.key, required this.imageFile});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScannerProvider>().setOriginalImage(widget.imageFile);
      context.read<ScannerProvider>().resetFilters();
    });
  }

  Future<void> _saveImage() async {
    final provider = context.read<ScannerProvider>();
    if (provider.processedImage == null) return;
    
    // Capturar el contexto antes del gap asíncrono
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final success = await ImageSaver.saveImage(
        provider.processedImage!,
        albumName: "DocScanner"
      );
      
      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Imagen guardada en la galería'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (mounted) { // Verificar que el widget sigue montado
          setState(() {
            _errorMessage = 'No se pudo guardar la imagen. Verifica los permisos.';
          });
        }
      }
    } catch (e) {
      if (mounted) { // Verificar que el widget sigue montado
        setState(() {
          _errorMessage = 'Error al guardar: $e';
        });
      }
    } finally {
      if (mounted) { // Verificar que el widget sigue montado
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _shareImage() async {
    final provider = context.read<ScannerProvider>();
    
    if (provider.processedImage != null) {
      // Capturar el contexto antes de la operación asincrónica
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      
      try {
        await Share.shareXFiles(
          [XFile(provider.processedImage!.path)],
          text: 'Documento escaneado con DocScanner'
        );
      } catch (e) {
        // Verificar que el widget sigue montado antes de usar el scaffoldMessenger
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Error al compartir: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Documento'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveImage,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareImage,
          ),
        ],
      ),
      body: Consumer<ScannerProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              // Imagen
              Expanded(
                flex: 3,
                child: Container(
                  margin: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Imagen procesada
                      if (provider.processedImage != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image.file(
                            provider.processedImage!,
                            fit: BoxFit.contain,
                          ),
                        )
                      else
                        const Center(
                          child: Text('No hay imagen para mostrar'),
                        ),
                        
                      // Indicador de procesamiento
                      if (provider.processingImage)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                        
                      // Indicador de guardado
                      if (_isSaving)
                        Container(
                          color: Colors.black54,
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Guardando imagen...',
                                style: TextStyle(color: Colors.white),
                              )
                            ],
                          ),
                        ),
                        
                      // Mensaje de error
                      if (_errorMessage != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.red,
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Opciones de procesamiento
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, -5),
                      ),
                    ],
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20.0),
                      topRight: Radius.circular(20.0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Opciones de Procesamiento',
                        style: TextStyle(
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16.0),

                      // Blanco y Negro
                      ProcessingOption(
                        title: 'Blanco y Negro',
                        widget: Switch(
                          value: provider.blackAndWhite,
                          onChanged: provider.processingImage 
                              ? null
                              : (value) => provider.setBlackAndWhite(value),
                          activeColor: Colors.indigo,
                        ),
                      ),

                      // Contraste
                      ProcessingOption(
                        title: 'Contraste',
                        widget: Slider(
                          value: provider.contrast.toDouble(),
                          min: -100,
                          max: 100,
                          divisions: 20,
                          label: provider.contrast.toString(),
                          onChanged: provider.processingImage 
                              ? null
                              : (value) => provider.setContrast(value.toInt()),
                          activeColor: Colors.indigo,
                        ),
                      ),

                      // Suavizado
                      ProcessingOption(
                        title: 'Suavizado',
                        widget: Slider(
                          value: provider.blurRadius,
                          min: 0,
                          max: 5,
                          divisions: 10,
                          label: provider.blurRadius.toStringAsFixed(1),
                          onChanged: provider.processingImage 
                              ? null
                              : (value) => provider.setBlurRadius(value),
                          activeColor: Colors.indigo,
                        ),
                      ),

                      // Botón reset
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: provider.processingImage
                              ? null
                              : provider.resetFilters,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Restablecer'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.indigo,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
