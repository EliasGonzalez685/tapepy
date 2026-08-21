import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/utils/imprimir_documento.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/cuota_plataforma_service.dart';

const _meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

/// Cuota propia de la plataforma (distinta de "Mis pagos", que es la
/// cuota interna a la asociación/parada) -- la ven los 3 roles que
/// pagan: conductor, presidente de parada y presidente de asociación.
/// El dueño de plataforma genera el cargo del mes; acá cada uno reporta
/// que ya pagó, igual que con los pagos internos. Si queda en deuda, el
/// carnet/QR deja de funcionar (banner de aviso abajo).
class MiCuotaPlataformaScreen extends StatefulWidget {
  final Usuario usuario;
  const MiCuotaPlataformaScreen({super.key, required this.usuario});

  @override
  State<MiCuotaPlataformaScreen> createState() => _MiCuotaPlataformaScreenState();
}

class _MiCuotaPlataformaScreenState extends State<MiCuotaPlataformaScreen> {
  final _service = CuotaPlataformaService();
  late Future<List<CuotaPlataformaItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarMia(widget.usuario.id);
  }

  void _refrescar() => setState(() {
        _future = _service.cargarMia(widget.usuario.id);
      });

  Future<void> _reportarPago(CuotaPlataformaItem cuota) async {
    final reportado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioReportarPago(cuota: cuota, usuario: widget.usuario, service: _service),
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

  void _verComprobante(CuotaPlataformaItem cuota) {
    final path = cuota.comprobanteUrl;
    if (path == null) return;
    imprimirArchivoDocumento(
      context: context,
      obtenerUrlFirmada: _service.obtenerUrlComprobante,
      path: path,
      nombreSugerido: 'comprobante_plataforma_${_meses[cuota.mes]}_${cuota.anio}.pdf',
    );
  }

  Color _colorEstado(CuotaPlataformaItem cuota) {
    if (cuota.enDeuda) return AppTheme.estadoUrgente;
    switch (cuota.estado) {
      case 'pagado':
        return AppTheme.estadoOk;
      case 'exonerado':
        return AppTheme.estadoOk;
      case 'pendiente':
        return AppTheme.estadoAtencion;
      default:
        return Colors.grey;
    }
  }

  String _labelEstado(CuotaPlataformaItem cuota) {
    if (cuota.enDeuda) return 'Atrasado';
    const labels = {
      'pagado': 'Pagado',
      'atrasado': 'Atrasado',
      'pendiente': 'Pendiente',
      'exonerado': 'Exonerado',
    };
    return labels[cuota.estado] ?? cuota.estado;
  }

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return Scaffold(
      appBar: AppBar(title: const Text('Cuota de plataforma')),
      body: FutureBuilder<List<CuotaPlataformaItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final cuotas = snapshot.data ?? [];
          final hayDeuda = cuotas.any((c) => c.enDeuda);

          if (cuotas.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                  child: Column(
                    children: [
                      Icon(Icons.workspace_premium_outlined,
                          size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      const Text('Todavía no tenés ningún cargo de plataforma', textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (hayDeuda) ...[
                _BannerDeuda(),
                const SizedBox(height: 12),
              ],
              ...cuotas.map((cuota) {
                final color = _colorEstado(cuota);
                final tieneComprobante = cuota.comprobanteUrl != null;
                final yaPagado = cuota.alDia;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
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
                                    Text('${_meses[cuota.mes]} ${cuota.anio}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(fontWeight: FontWeight.w600)),
                                    Text(cuota.motivo,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    Text('₲ ${formatoMonto.format(cuota.monto)}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600)),
                                    if (yaPagado && cuota.metodoPago != null)
                                      Text('Pagado por: ${_labelMetodo(cuota.metodoPago)}',
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
                                child: Text(_labelEstado(cuota),
                                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (tieneComprobante)
                            OutlinedButton.icon(
                              onPressed: () => _verComprobante(cuota),
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('Ver comprobante'),
                            )
                          else if (!yaPagado)
                            OutlinedButton.icon(
                              onPressed: () => _reportarPago(cuota),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Reportar pago'),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _BannerDeuda extends StatelessWidget {
  const _BannerDeuda();

  @override
  Widget build(BuildContext context) {
    return Container(
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
              'Tenés una cuota de plataforma atrasada: tu carnet y código QR no van a mostrarse como vigentes hasta que se regularice.',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.estadoUrgente, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormularioReportarPago extends StatefulWidget {
  final CuotaPlataformaItem cuota;
  final Usuario usuario;
  final CuotaPlataformaService service;
  const _FormularioReportarPago({required this.cuota, required this.usuario, required this.service});

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
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId == null) return;
    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      final bytes = _metodo == 'transferencia' ? await _archivo!.readAsBytes() : null;
      final extension = _metodo == 'transferencia' ? _archivo!.name.split('.').last : null;
      await widget.service.reportarPago(
        cuotaId: widget.cuota.id,
        usuarioId: widget.usuario.id,
        organizacionId: organizacionId,
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
            '${widget.cuota.motivo} · ${_meses[widget.cuota.mes]} ${widget.cuota.anio}',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Confirmar pago'),
          ),
        ],
      ),
    );
  }
}
