import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/conductor_service.dart';

const _tiposDocumento = {
  'cedula': ('Cédula', 'personal'),
  'licencia_conducir': ('Licencia de conducir', 'personal'),
  'antecedentes_policiales': ('Antecedentes policiales', 'personal'),
  'seguro_vehicular': ('Seguro vehicular', 'vehiculo'),
  'revision_tecnica': ('Revisión técnica', 'vehiculo'),
  'carta_verde': ('Carta verde', 'vehiculo'),
  'habilitacion_vehicular': ('Habilitación vehicular', 'vehiculo'),
  'cedula_verde': ('Cédula verde', 'vehiculo'),
  'otro': ('Otro documento', 'personal'),
};

/// Documentos propios del conductor. Acá es donde se cumple la regla de
/// producto: cada conductor sube los suyos, nadie lo hace por él — y es
/// responsable de lo que suba o de lo que le falte.
class MisDocumentosScreen extends StatefulWidget {
  final ConductorPerfil perfil;
  final String usuarioId;
  const MisDocumentosScreen({super.key, required this.perfil, required this.usuarioId});

  @override
  State<MisDocumentosScreen> createState() => _MisDocumentosScreenState();
}

class _MisDocumentosScreenState extends State<MisDocumentosScreen> {
  final _service = ConductorService();
  late Future<List<DocumentoConductorItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarDocumentos(widget.perfil.conductorId);
  }

  void _refrescar() => setState(() {
        _future = _service.cargarDocumentos(widget.perfil.conductorId);
      });

  Future<void> _abrirFormularioSubida() async {
    final subido = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FormularioDocumento(
        perfil: widget.perfil,
        usuarioId: widget.usuarioId,
        service: _service,
      ),
    );
    if (subido == true) _refrescar();
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'vigente':
        return AppTheme.estadoOk;
      case 'por_vencer':
        return AppTheme.estadoAtencion;
      case 'vencido':
        return AppTheme.estadoUrgente;
      default:
        return Colors.grey;
    }
  }

  String _labelEstado(String estado) {
    const labels = {'vigente': 'Vigente', 'por_vencer': 'Por vencer', 'vencido': 'Vencido'};
    return labels[estado] ?? estado;
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Mis documentos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormularioSubida,
        backgroundColor: AppTheme.rojoInstitucional,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file_outlined, color: Colors.white),
        label: const Text('Subir documento', style: TextStyle(color: Colors.white)),
      ),
      body: FutureBuilder<List<DocumentoConductorItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data ?? [];
          if (docs.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                  child: Column(
                    children: [
                      Icon(Icons.description_outlined,
                          size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      const Text('Todavía no subiste ningún documento', textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(
                        'Tocá "Subir documento" para empezar.',
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
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final color = _colorEstado(doc.estado);
              final etiquetaTipo = _tiposDocumento[doc.tipo]?.$1 ?? doc.tipo;
              final tieneDescripcion = doc.descripcion != null && doc.descripcion!.isNotEmpty;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      IconBadge(icono: Icons.description_outlined, color: color, diametro: 44),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tieneDescripcion ? doc.descripcion! : etiquetaTipo,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            if (tieneDescripcion)
                              Text(etiquetaTipo,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            if (doc.fechaVencimiento != null)
                              Text('Vence ${formatoFecha.format(doc.fechaVencimiento!)}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_labelEstado(doc.estado),
                            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
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

class _FormularioDocumento extends StatefulWidget {
  final ConductorPerfil perfil;
  final String usuarioId;
  final ConductorService service;
  const _FormularioDocumento({
    required this.perfil,
    required this.usuarioId,
    required this.service,
  });

  @override
  State<_FormularioDocumento> createState() => _FormularioDocumentoState();
}

class _FormularioDocumentoState extends State<_FormularioDocumento> {
  String _tipo = 'cedula';
  DateTime? _vencimiento;
  XFile? _archivo;
  bool _subiendo = false;
  final _descripcionController = TextEditingController();

  bool get _esOtro => _tipo == 'otro';

  @override
  void dispose() {
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _elegirArchivo() async {
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
    if (archivo != null) setState(() => _archivo = archivo);
  }

  Future<void> _elegirVencimiento() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (fecha != null) setState(() => _vencimiento = fecha);
  }

  Future<void> _subir() async {
    if (_archivo == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Elegí una foto del documento')));
      return;
    }
    if (_esOtro && _descripcionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Contá qué documento es')));
      return;
    }
    setState(() => _subiendo = true);
    try {
      final bytes = await _archivo!.readAsBytes();
      final extension = _archivo!.name.split('.').last;
      final categoria = _tiposDocumento[_tipo]?.$2 ?? 'personal';

      await widget.service.subirDocumento(
        organizacionId: widget.perfil.organizacionId,
        usuarioId: widget.usuarioId,
        conductorId: widget.perfil.conductorId,
        categoria: categoria,
        tipo: _tipo,
        bytes: bytes,
        extension: extension,
        fechaVencimiento: _vencimiento,
        descripcion:
            _descripcionController.text.trim().isEmpty ? null : _descripcionController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo subir. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Subir documento', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _tipo,
            decoration: const InputDecoration(labelText: 'Tipo de documento', border: OutlineInputBorder()),
            items: _tiposDocumento.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.$1)))
                .toList(),
            onChanged: (value) => setState(() => _tipo = value ?? _tipo),
          ),
          if (_esOtro) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _descripcionController,
              decoration: const InputDecoration(
                labelText: 'Qué documento es',
                hintText: 'Ej: Carta de recomendación, comprobante de domicilio',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _elegirArchivo,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_archivo == null ? 'Elegir foto del documento' : 'Foto seleccionada ✓'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _elegirVencimiento,
            icon: const Icon(Icons.event_outlined),
            label: Text(_vencimiento == null
                ? 'Fecha de vencimiento (opcional)'
                : 'Vence ${formatoFecha.format(_vencimiento!)}'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _subiendo ? null : _subir,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
            child: _subiendo
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Subir'),
          ),
        ],
      ),
    );
  }
}
