import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/utils/imprimir_documento.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/cuota_plataforma_service.dart';

const _meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

const _labelsEstado = {
  'pagado': 'Pagado',
  'exonerado': 'Exonerado',
  'pendiente': 'Pendiente',
  'moroso': 'Moroso',
};

/// Cuota propia de la plataforma (distinta de "Mis pagos", que es la
/// cuota interna a la asociación/parada) -- la ven los 3 roles que
/// pagan: conductor, presidente de parada y presidente de asociación.
/// Autoservicio puro (pedido de Elias 2026-08-21): no hay ningún cargo
/// pre-generado por el dueño -- cada quien reporta acá que ya pagó el
/// mes en curso, y si no lo hizo antes del día 15 aparece como
/// moroso automáticamente. Si queda en deuda, el carnet/QR deja de
/// funcionar (banner de aviso abajo).
class MiCuotaPlataformaScreen extends StatefulWidget {
  final Usuario usuario;
  const MiCuotaPlataformaScreen({super.key, required this.usuario});

  @override
  State<MiCuotaPlataformaScreen> createState() => _MiCuotaPlataformaScreenState();
}

class _MiCuotaPlataformaScreenState extends State<MiCuotaPlataformaScreen> {
  final _service = CuotaPlataformaService();
  Future<EstadoCuotaPlataforma>? _future;
  late Future<List<CuotaPlataformaItem>> _historialFuture;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId != null) {
      _future = _service.cargarMiEstado(usuarioId: widget.usuario.id, organizacionId: organizacionId);
    }
    _historialFuture = _service.cargarMia(widget.usuario.id);
  }

  void _refrescar() => setState(_cargar);

  Future<void> _reportarPago() async {
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId == null) return;
    final reportado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioReportarPago(
        usuarioId: widget.usuario.id,
        organizacionId: organizacionId,
        service: _service,
      ),
    );
    if (reportado == true) _refrescar();
  }

  String _labelMetodo(String? metodo) {
    switch (metodo) {
      case 'efectivo':
        return 'Efectivo';
      case 'transferencia':
        return 'Transferencia';
      default:
        return '';
    }
  }

  void _verComprobante(String? path) {
    if (path == null) return;
    imprimirArchivoDocumento(
      context: context,
      obtenerUrlFirmada: _service.obtenerUrlComprobante,
      path: path,
      nombreSugerido: 'comprobante_plataforma.pdf',
    );
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'pagado':
      case 'exonerado':
        return AppTheme.estadoOk;
      case 'moroso':
        return AppTheme.estadoUrgente;
      default:
        return AppTheme.estadoAtencion;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return Scaffold(
      appBar: AppBar(title: const Text('Cuota de plataforma')),
      body: _future == null
          ? const Center(child: Text('No se pudo determinar tu organización.'))
          : RefreshIndicator(
              onRefresh: () async {
                _refrescar();
                await _future;
              },
              child: FutureBuilder<EstadoCuotaPlataforma>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData) {
                    return Center(child: Text('No se pudo cargar: ${snapshot.error}'));
                  }
                  final estado = snapshot.data!;
                  final color = _colorEstado(estado.estado);
                  final tieneComprobante = estado.comprobanteUrl != null;

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (estado.enDeuda) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.estadoUrgente.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: AppTheme.estadoUrgente, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Tenés la cuota de plataforma atrasada: tu carnet y código QR no van a mostrarse como vigentes hasta que se regularice.',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600, color: AppTheme.estadoUrgente, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  IconBadge(icono: Icons.workspace_premium_outlined, color: color, diametro: 44),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Este mes',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(fontWeight: FontWeight.w600)),
                                        Text('₲ ${formatoMonto.format(estado.monto)}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w600)),
                                        if (estado.alDia && estado.metodoPago != null)
                                          Text('Pagado por: ${_labelMetodo(estado.metodoPago)}',
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
                                    child: Text(_labelsEstado[estado.estado] ?? estado.estado,
                                        style:
                                            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (tieneComprobante)
                                OutlinedButton.icon(
                                  onPressed: () => _verComprobante(estado.comprobanteUrl),
                                  icon: const Icon(Icons.receipt_long_outlined),
                                  label: const Text('Ver comprobante'),
                                )
                              else if (!estado.alDia)
                                OutlinedButton.icon(
                                  onPressed: _reportarPago,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Reportar pago'),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Historial', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      FutureBuilder<List<CuotaPlataformaItem>>(
                        future: _historialFuture,
                        builder: (context, snapshotHistorial) {
                          if (snapshotHistorial.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final historial = snapshotHistorial.data ?? [];
                          if (historial.isEmpty) {
                            return const Text('Todavía no reportaste ningún pago.');
                          }
                          return Column(
                            children: historial.map((c) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  dense: true,
                                  title: Text('${_meses[c.mes]} ${c.anio}'),
                                  subtitle: Text('₲ ${formatoMonto.format(c.monto)}'),
                                  trailing: Text(_labelsEstado[c.estado] ?? c.estado),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _FormularioReportarPago extends StatefulWidget {
  final String usuarioId;
  final String organizacionId;
  final CuotaPlataformaService service;
  const _FormularioReportarPago({
    required this.usuarioId,
    required this.organizacionId,
    required this.service,
  });

  @override
  State<_FormularioReportarPago> createState() => _FormularioReportarPagoState();
}

class _FormularioReportarPagoState extends State<_FormularioReportarPago> {
  String _metodo = 'efectivo';
  XFile? _archivo;
  DateTime _fechaPago = DateTime.now();
  bool _subiendo = false;
  String? _error;

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
    final archivo = await ImagePicker().pickImage(source: origen, maxWidth: 1600, imageQuality: 85);
    if (archivo != null) setState(() => _archivo = archivo);
  }

  Future<void> _elegirFechaPago() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaPago,
      firstDate: DateTime(_fechaPago.year - 1),
      lastDate: DateTime.now(),
    );
    if (fecha != null) setState(() => _fechaPago = fecha);
  }

  Future<void> _subir() async {
    if (_metodo == 'transferencia' && _archivo == null) {
      setState(() => _error = 'Elegí una foto del comprobante');
      return;
    }
    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      final bytes = _metodo == 'transferencia' ? await _archivo!.readAsBytes() : null;
      final extension = _metodo == 'transferencia' ? _archivo!.name.split('.').last : null;
      await widget.service.reportarPago(
        usuarioId: widget.usuarioId,
        organizacionId: widget.organizacionId,
        metodoPago: _metodo,
        fechaPago: _fechaPago,
        bytes: bytes,
        extension: extension,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CuotaPlataformaException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo registrar el pago. Intentá de nuevo.');
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
          Text('Reportar pago', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Cuota de plataforma',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text('Medio de pago', style: Theme.of(context).textTheme.bodyMedium),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'efectivo',
            groupValue: _metodo,
            title: const Text('Efectivo'),
            onChanged: (v) => setState(() => _metodo = v!),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'transferencia',
            groupValue: _metodo,
            title: const Text('Transferencia'),
            onChanged: (v) => setState(() => _metodo = v!),
          ),
          if (_metodo == 'transferencia') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _elegirArchivo,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_archivo == null ? 'Elegir foto del comprobante' : 'Foto seleccionada ✓'),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _elegirFechaPago,
            icon: const Icon(Icons.event_outlined),
            label: Text('Fecha de pago: ${formatoFecha.format(_fechaPago)}'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _subiendo ? null : _subir,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
            child: _subiendo
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Confirmar pago'),
          ),
        ],
      ),
    );
  }
}
