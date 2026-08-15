import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../data/conductor_service.dart';

/// Alta/edición del vehículo propio. El conductor es el único que carga
/// estos datos — nadie más los completa por él. Las dos fotos (frente
/// con chapa, y de lejos) son obligatorias, no un extra.
class MiVehiculoScreen extends StatefulWidget {
  final ConductorPerfil perfil;
  const MiVehiculoScreen({super.key, required this.perfil});

  @override
  State<MiVehiculoScreen> createState() => _MiVehiculoScreenState();
}

class _MiVehiculoScreenState extends State<MiVehiculoScreen> {
  final _service = ConductorService();
  final _formKey = GlobalKey<FormState>();
  late final _marcaController =
      TextEditingController(text: widget.perfil.vehiculo?.marca ?? '');
  late final _modeloController =
      TextEditingController(text: widget.perfil.vehiculo?.modelo ?? '');
  late final _anioController =
      TextEditingController(text: widget.perfil.vehiculo?.anio?.toString() ?? '');
  late final _chapaController =
      TextEditingController(text: widget.perfil.vehiculo?.chapa ?? '');
  late final _colorController =
      TextEditingController(text: widget.perfil.vehiculo?.color ?? '');
  late final _resolucionController =
      TextEditingController(text: widget.perfil.vehiculo?.resolucionNumero ?? '');

  bool _guardando = false;
  VehiculoFotoSlot? _subiendoSlot;
  String? _vehiculoId;
  String? _fotoFrente;
  String? _fotoLejos;
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _fotoFrente = widget.perfil.vehiculo?.fotoFrenteChapa;
    _fotoLejos = widget.perfil.vehiculo?.fotoLejos;
    _initFuture = _inicializar();
  }

  /// Si todavía no existe la fila de vehículo, la crea vacía acá mismo
  /// para tener un id y poder subir fotos aunque no se haya guardado
  /// marca/modelo/etc. todavía.
  Future<void> _inicializar() async {
    if (widget.perfil.vehiculo?.id != null) {
      _vehiculoId = widget.perfil.vehiculo!.id;
      return;
    }
    _vehiculoId = await _service.crearVehiculoVacio(
      conductorId: widget.perfil.conductorId,
      organizacionId: widget.perfil.organizacionId,
    );
  }

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _chapaController.dispose();
    _colorController.dispose();
    _resolucionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vehiculoId == null) return;
    setState(() => _guardando = true);
    try {
      await _service.actualizarVehiculo(
        vehiculoId: _vehiculoId!,
        marca: _marcaController.text.trim().isEmpty ? null : _marcaController.text.trim(),
        modelo: _modeloController.text.trim().isEmpty ? null : _modeloController.text.trim(),
        anio: int.tryParse(_anioController.text.trim()),
        chapa: _chapaController.text.trim().isEmpty ? null : _chapaController.text.trim(),
        color: _colorController.text.trim().isEmpty ? null : _colorController.text.trim(),
        resolucionNumero:
            _resolucionController.text.trim().isEmpty ? null : _resolucionController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Vehículo guardado')));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo guardar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _tomarFoto(VehiculoFotoSlot slot) async {
    if (_vehiculoId == null) return;
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
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

    final archivo =
        await ImagePicker().pickImage(source: origen, maxWidth: 1600, imageQuality: 85);
    if (archivo == null) return;

    setState(() => _subiendoSlot = slot);
    try {
      final bytes = await archivo.readAsBytes();
      final extension = archivo.name.split('.').last;
      final path = await _service.subirFotoVehiculo(
        organizacionId: widget.perfil.organizacionId,
        usuarioId: widget.perfil.usuarioId,
        vehiculoId: _vehiculoId!,
        slot: slot,
        bytes: bytes,
        extension: extension,
      );
      if (!mounted) return;
      setState(() {
        if (slot == VehiculoFotoSlot.frente) {
          _fotoFrente = path;
        } else {
          _fotoLejos = path;
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo subir la foto. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _subiendoSlot = null);
    }
  }

  Future<void> _eliminarFoto(VehiculoFotoSlot slot) async {
    if (_vehiculoId == null) return;
    final path = slot == VehiculoFotoSlot.frente ? _fotoFrente : _fotoLejos;
    if (path == null) return;
    setState(() {
      if (slot == VehiculoFotoSlot.frente) {
        _fotoFrente = null;
      } else {
        _fotoLejos = null;
      }
    });
    try {
      await _service.eliminarFotoVehiculo(vehiculoId: _vehiculoId!, slot: slot, path: path);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (slot == VehiculoFotoSlot.frente) {
          _fotoFrente = path;
        } else {
          _fotoLejos = path;
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo eliminar la foto.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi vehículo')),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  TextFormField(
                    controller: _marcaController,
                    decoration:
                        const InputDecoration(labelText: 'Marca', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _modeloController,
                    decoration:
                        const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _anioController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Año', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _chapaController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'Chapa / patente', border: OutlineInputBorder()),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Ingresá la chapa';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _colorController,
                    decoration:
                        const InputDecoration(labelText: 'Color', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _resolucionController,
                    decoration: const InputDecoration(
                      labelText: 'Resolución Nº',
                      hintText: 'Ej: 244/15',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text('Fotos del vehículo',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      const Text('*', style: TextStyle(color: AppTheme.estadoUrgente, fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Obligatorias las dos.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SlotFoto(
                          slot: VehiculoFotoSlot.frente,
                          path: _fotoFrente,
                          subiendo: _subiendoSlot == VehiculoFotoSlot.frente,
                          service: _service,
                          onTomar: () => _tomarFoto(VehiculoFotoSlot.frente),
                          onEliminar: () => _eliminarFoto(VehiculoFotoSlot.frente),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SlotFoto(
                          slot: VehiculoFotoSlot.lejos,
                          path: _fotoLejos,
                          subiendo: _subiendoSlot == VehiculoFotoSlot.lejos,
                          service: _service,
                          onTomar: () => _tomarFoto(VehiculoFotoSlot.lejos),
                          onEliminar: () => _eliminarFoto(VehiculoFotoSlot.lejos),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                    child: _guardando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Guardar'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlotFoto extends StatelessWidget {
  final VehiculoFotoSlot slot;
  final String? path;
  final bool subiendo;
  final ConductorService service;
  final VoidCallback onTomar;
  final VoidCallback onEliminar;

  const _SlotFoto({
    required this.slot,
    required this.path,
    required this.subiendo,
    required this.service,
    required this.onTomar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(slot.etiqueta,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: subiendo ? null : onTomar,
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.rojoInstitucional.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.rojoInstitucional.withValues(alpha: 0.4)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: path == null
                      ? Center(
                          child: subiendo
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.add_a_photo_outlined,
                                  color: AppTheme.rojoInstitucional),
                        )
                      : FutureBuilder<String>(
                          future: service.obtenerUrlFirmada(path!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2)));
                            }
                            return Image.network(snapshot.data!, fit: BoxFit.cover);
                          },
                        ),
                ),
                if (path != null && !subiendo)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: onEliminar,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
