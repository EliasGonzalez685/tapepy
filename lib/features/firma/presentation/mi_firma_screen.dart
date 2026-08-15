import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../data/firma_service.dart';

/// Pantalla para que el presidente de asociación o el presidente de una
/// parada suba (o reemplace) la imagen de su firma — se usa después
/// para estampar los listados impresos, propios o de otro presidente
/// que se la haya autorizado (ver ImprimirListadoScreen).
class MiFirmaScreen extends StatefulWidget {
  final Usuario usuario;
  const MiFirmaScreen({super.key, required this.usuario});

  @override
  State<MiFirmaScreen> createState() => _MiFirmaScreenState();
}

class _MiFirmaScreenState extends State<MiFirmaScreen> {
  final _service = FirmaService();
  final _picker = ImagePicker();
  bool _cargando = true;
  bool _subiendo = false;
  String? _urlPreview;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final path = await _service.cargarFirmaUrl(widget.usuario.id);
      String? url;
      if (path != null) {
        url = await _service.obtenerUrlFirmada(path);
      }
      if (!mounted) return;
      setState(() => _urlPreview = url);
    } catch (_) {
      // Sin firma todavía o error de red: se queda en estado vacío.
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _elegirYSubir() async {
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId == null) return;

    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto de la firma'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (origen == null) return;

    final archivo = await _picker.pickImage(
      source: origen,
      maxWidth: 1000,
      maxHeight: 1000,
      imageQuality: 90,
    );
    if (archivo == null) return;

    setState(() => _subiendo = true);
    try {
      final bytes = await archivo.readAsBytes();
      await _service.subirFirma(
        usuarioId: widget.usuario.id,
        organizacionId: organizacionId,
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Firma actualizada')));
      await _cargar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo subir la firma. Intentá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi firma digital')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Esta firma se usa para estampar los listados que imprimas, y para autorizar '
            'a otro presidente a usarla en los suyos cuando te lo pida.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _cargando
                        ? const Center(child: CircularProgressIndicator())
                        : _urlPreview != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(_urlPreview!, fit: BoxFit.contain),
                              )
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.draw_outlined,
                                        size: 40, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Todavía no subiste tu firma',
                                      style: TextStyle(color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _subiendo ? null : _elegirYSubir,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                    icon: _subiendo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_outlined),
                    label: Text(_urlPreview != null ? 'Cambiar firma' : 'Subir firma'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
