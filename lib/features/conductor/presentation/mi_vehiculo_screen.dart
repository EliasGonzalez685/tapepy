import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/conductor_service.dart';

/// Lista de vehículos del conductor — puede tener más de uno (ver
/// [[project_traude_multivehiculo]]). Cada tarjeta tiene un switch para
/// decidir si ese vehículo entra en los listados imprimibles; los
/// presidentes también pueden alternar ese mismo switch desde su lado
/// (RLS lo permite), así que acá se refleja el estado real cada vez que
/// se refresca, no solo lo que el conductor haya tocado.
class MiVehiculoScreen extends StatefulWidget {
  final ConductorPerfil perfil;
  const MiVehiculoScreen({super.key, required this.perfil});

  @override
  State<MiVehiculoScreen> createState() => _MiVehiculoScreenState();
}

class _MiVehiculoScreenState extends State<MiVehiculoScreen> {
  final _service = ConductorService();
  late Future<List<VehiculoInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = Future.value(widget.perfil.vehiculos);
  }

  Future<void> _refrescar() async {
    final perfil = await _service.cargarPerfil(widget.perfil.usuarioId);
    setState(() => _future = Future.value(perfil?.vehiculos ?? []));
  }

  Future<void> _agregar() async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _VehiculoFormScreen(perfil: widget.perfil, vehiculo: null)),
    );
    if (guardado == true) _refrescar();
  }

  Future<void> _editar(VehiculoInfo vehiculo) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _VehiculoFormScreen(perfil: widget.perfil, vehiculo: vehiculo)),
    );
    if (guardado == true) _refrescar();
  }

  Future<void> _alternarIncluirEnListado(VehiculoInfo vehiculo, bool valor) async {
    if (vehiculo.id == null) return;
    try {
      await _service.alternarIncluirEnListado(vehiculoId: vehiculo.id!, valor: valor);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo actualizar. Intentá de nuevo.')));
    } finally {
      _refrescar();
    }
  }

  Future<void> _eliminar(VehiculoInfo vehiculo) async {
    if (vehiculo.id == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar vehículo?'),
        content: Text(
          'Se va a borrar ${[
            vehiculo.marca,
            vehiculo.modelo,
          ].where((e) => e != null && e.isNotEmpty).join(' ').trim().isEmpty ? 'este vehículo' : '${vehiculo.marca ?? ''} ${vehiculo.modelo ?? ''}'.trim()} y sus fotos. No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Eliminar', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _service.eliminarVehiculo(
        vehiculoId: vehiculo.id!,
        fotoFrenteChapa: vehiculo.fotoFrenteChapa,
        fotoLejos: vehiculo.fotoLejos,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehículo eliminado')));
      _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo eliminar. Intentá de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis vehículos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregar,
        backgroundColor: AppTheme.rojoInstitucional,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Agregar vehículo', style: TextStyle(color: Colors.white)),
      ),
      body: FutureBuilder<List<VehiculoInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final vehiculos = snapshot.data ?? [];
          if (vehiculos.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                  child: Column(
                    children: [
                      Icon(Icons.directions_car_filled_outlined,
                          size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      const Text('Todavía no cargaste ningún vehículo', textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(
                        'Tocá "Agregar vehículo" para empezar. Podés cargar más de uno.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: vehiculos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final vehiculo = vehiculos[index];
              final titulo = [vehiculo.marca, vehiculo.modelo]
                  .where((e) => e != null && e.isNotEmpty)
                  .join(' ');
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconBadge(
                            icono: Icons.directions_car_filled_outlined,
                            color: AppTheme.rojoInstitucional,
                            diametro: 44,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(titulo.isEmpty ? 'Sin datos todavía' : titulo,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                if (vehiculo.chapa != null)
                                  Text(vehiculo.chapa!,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Editar',
                            onPressed: () => _editar(vehiculo),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                            tooltip: 'Eliminar',
                            onPressed: () => _eliminar(vehiculo),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Incluir en listados impresos',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Switch(
                            value: vehiculo.incluirEnListado,
                            activeThumbColor: AppTheme.rojoInstitucional,
                            onChanged: (valor) => _alternarIncluirEnListado(vehiculo, valor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Alta/edición de un vehículo puntual. Las dos fotos (frente con
/// chapa, y de lejos) son obligatorias, no un extra.
class _VehiculoFormScreen extends StatefulWidget {
  final ConductorPerfil perfil;
  final VehiculoInfo? vehiculo; // null = alta de uno nuevo
  const _VehiculoFormScreen({required this.perfil, required this.vehiculo});

  @override
  State<_VehiculoFormScreen> createState() => _VehiculoFormScreenState();
}

class _VehiculoFormScreenState extends State<_VehiculoFormScreen> {
  final _service = ConductorService();
  final _formKey = GlobalKey<FormState>();
  late final _marcaController = TextEditingController(text: widget.vehiculo?.marca ?? '');
  late final _modeloController = TextEditingController(text: widget.vehiculo?.modelo ?? '');
  late final _anioController = TextEditingController(text: widget.vehiculo?.anio?.toString() ?? '');
  late final _chapaController = TextEditingController(text: widget.vehiculo?.chapa ?? '');
  late final _colorController = TextEditingController(text: widget.vehiculo?.color ?? '');
  late final _resolucionController =
      TextEditingController(text: widget.vehiculo?.resolucionNumero ?? '');

  bool _guardando = false;
  VehiculoFotoSlot? _subiendoSlot;
  String? _vehiculoId;
  String? _fotoFrente;
  String? _fotoLejos;
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _fotoFrente = widget.vehiculo?.fotoFrenteChapa;
    _fotoLejos = widget.vehiculo?.fotoLejos;
    _initFuture = _inicializar();
  }

  /// Si es un vehículo nuevo, crea la fila vacía acá mismo para tener un
  /// id y poder subir fotos aunque todavía no se haya guardado
  /// marca/modelo/etc.
  Future<void> _inicializar() async {
    if (widget.vehiculo?.id != null) {
      _vehiculoId = widget.vehiculo!.id;
      return;
    }
    _vehiculoId = await _service.agregarVehiculo(
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
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: Text(widget.vehiculo == null ? 'Agregar vehículo' : 'Editar vehículo')),
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
