import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/imprimir_documento.dart';
import '../../../shared/utils/seleccionar_foto.dart';
import '../../../shared/widgets/combinar_documentos_sheet.dart';
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
/// responsable de lo que suba o de lo que le falte. Pantalla compartida
/// por los tres roles que suben documentos (conductor, presidente de
/// parada, presidente de asociación vía "Mi perfil de socio") -- pedido
/// de Elias 2026-08-22: todos tienen que poder VER lo que ya subieron,
/// no solo subir.
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

  Future<void> _verDocumento(DocumentoConductorItem doc) async {
    final etiquetaTipo = _tiposDocumento[doc.tipo]?.$1 ?? doc.tipo;
    await imprimirArchivoDocumento(
      context: context,
      obtenerUrlFirmada: _service.obtenerUrlFirmada,
      path: doc.archivoUrl,
      nombreSugerido: '$etiquetaTipo.pdf',
    );
  }

  Future<void> _compartirDocumento(DocumentoConductorItem doc) async {
    final etiquetaTipo = _tiposDocumento[doc.tipo]?.$1 ?? doc.tipo;
    await compartirArchivoDocumento(
      context: context,
      obtenerUrlFirmada: _service.obtenerUrlFirmada,
      path: doc.archivoUrl,
      nombreSugerido: '$etiquetaTipo.pdf',
    );
  }

  Future<void> _abrirCombinar() async {
    final docs = await _future;
    if (!mounted) return;
    if (docs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesitás al menos 2 documentos subidos para juntar.')),
      );
      return;
    }
    mostrarCombinarDocumentosSheet(
      context,
      documentos: docs
          .map((d) => (
                id: d.id,
                etiqueta: (d.descripcion != null && d.descripcion!.isNotEmpty)
                    ? d.descripcion!
                    : (_tiposDocumento[d.tipo]?.$1 ?? d.tipo),
                archivoUrl: d.archivoUrl,
              ))
          .toList(),
      obtenerUrlFirmada: _service.obtenerUrlFirmada,
    );
  }

  Future<void> _eliminarDocumento(DocumentoConductorItem doc) async {
    final etiquetaTipo = _tiposDocumento[doc.tipo]?.$1 ?? doc.tipo;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar documento?'),
        content: Text('Se va a borrar "$etiquetaTipo". No se puede deshacer.'),
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
      await _service.eliminarDocumento(documentoId: doc.id, archivoUrl: doc.archivoUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Documento eliminado')));
      _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo eliminar. Intentá de nuevo.')));
    }
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
      appBar: AppBar(
        title: const Text('Mis documentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_view_outlined),
            tooltip: 'Juntar documentos en una hoja',
            onPressed: _abrirCombinar,
          ),
        ],
      ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
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
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _verDocumento(doc),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Ver'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.share_outlined),
                            tooltip: 'Compartir',
                            onPressed: () => _compartirDocumento(doc),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                            tooltip: 'Eliminar',
                            onPressed: () => _eliminarDocumento(doc),
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
  // Una o más fotos -- documentos con frente y verso mandan las dos, se
  // combinan en un solo PDF al subir (ConductorService.subirDocumento).
  final List<XFile> _archivos = [];
  bool _subiendo = false;
  // Solo aplica cuando hay exactamente 2 fotos (frente/verso): permite
  // ponerlas lado a lado arriba de una sola hoja en vez de una hoja por
  // foto (pedido de Elias 2026-08-22).
  bool _ladoALado = true;
  final _descripcionController = TextEditingController();

  bool get _esOtro => _tipo == 'otro';

  @override
  void dispose() {
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _agregarFoto() async {
    final archivo = await seleccionarYRecortarFoto(context);
    if (archivo != null) setState(() => _archivos.add(archivo));
  }

  void _quitarFoto(int index) {
    setState(() => _archivos.removeAt(index));
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
    if (_archivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sacá o elegí al menos una foto del documento')),
      );
      return;
    }
    if (_esOtro && _descripcionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Contá qué documento es')));
      return;
    }
    setState(() => _subiendo = true);
    try {
      final paginas = await Future.wait(_archivos.map((a) => a.readAsBytes()));
      final categoria = _tiposDocumento[_tipo]?.$2 ?? 'personal';

      await widget.service.subirDocumento(
        organizacionId: widget.perfil.organizacionId,
        usuarioId: widget.usuarioId,
        conductorId: widget.perfil.conductorId,
        categoria: categoria,
        tipo: _tipo,
        paginas: paginas,
        fechaVencimiento: _vencimiento,
        descripcion:
            _descripcionController.text.trim().isEmpty ? null : _descripcionController.text.trim(),
        ladoALado: _archivos.length == 2 && _ladoALado,
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
          Text('Fotos del documento', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            'Si tiene frente y verso, sacá las dos fotos -- se juntan en un solo PDF.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (_archivos.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _archivos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.rojoInstitucional.withValues(alpha: 0.4)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.file(
                          File(_archivos[index].path),
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => _quitarFoto(index),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          if (_archivos.length == 2) ...[
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _ladoALado,
              onChanged: (value) => setState(() => _ladoALado = value),
              title: const Text('Frente y verso lado a lado en la misma hoja'),
              subtitle: const Text('Si lo apagás, cada foto va en su propia hoja'),
              activeColor: AppTheme.rojoInstitucional,
            ),
          ],
          if (_archivos.isNotEmpty) const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _agregarFoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_archivos.isEmpty ? 'Elegir foto del documento' : 'Agregar otra foto (verso, etc.)'),
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
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.rojoInstitucional,
              foregroundColor: Colors.white,
            ),
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
