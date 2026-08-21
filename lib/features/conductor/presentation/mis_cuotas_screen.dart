import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/utils/imprimir_documento.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../plataforma/data/cuota_plataforma_service.dart';
import '../data/conductor_service.dart';

const _meses = [
  '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
];

/// Pagos propios: cuota de plataforma (a TapePy, autoservicio -- ver
/// [_SeccionCuotaPlataforma]) + cuotas internas a la parada/asociación
/// (el presidente carga el pago que corresponde, individual o grupal,
/// ver lotes_pago, y el conductor reporta que ya pagó). En ambos casos
/// reportar el pago (efectivo o transferencia, con comprobante si
/// corresponde) lo marca como pagado. Pantalla compartida: la usa el
/// conductor directo y también presidente de parada/asociación (vía
/// "Mis pagos" en Mi perfil de socio), así que la cuota de plataforma
/// que ven acá es siempre la propia, sin importar el rol.
class MisCuotasScreen extends StatefulWidget {
  final Usuario usuario;
  const MisCuotasScreen({super.key, required this.usuario});

  @override
  State<MisCuotasScreen> createState() => _MisCuotasScreenState();
}

class _MisCuotasScreenState extends State<MisCuotasScreen> {
  final _service = ConductorService();
  final _servicioPlataforma = CuotaPlataformaService();
  late Future<List<CuotaPropia>> _future;
  Future<EstadoCuotaPlataforma>? _futurePlataforma;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _service.cargarCuotas(widget.usuario.id);
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId != null) {
      _futurePlataforma =
          _servicioPlataforma.cargarMiEstado(usuarioId: widget.usuario.id, organizacionId: organizacionId);
    }
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await Future.wait([_future, if (_futurePlataforma != null) _futurePlataforma!]);
  }

  Future<void> _reportarPago(CuotaPropia cuota) async {
    final reportado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioReportarPago(
        cuota: cuota,
        usuario: widget.usuario,
        service: _service,
      ),
    );
    if (reportado == true) _refrescar();
  }

  Future<void> _reportarPagoPlataforma() async {
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId == null) return;
    final reportado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioReportarPagoPlataforma(
        usuarioId: widget.usuario.id,
        organizacionId: organizacionId,
        service: _servicioPlataforma,
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

  void _verComprobante(CuotaPropia cuota) {
    final path = cuota.comprobanteUrl;
    if (path == null) return;
    imprimirArchivoDocumento(
      context: context,
      obtenerUrlFirmada: _service.obtenerUrlComprobante,
      path: path,
      nombreSugerido: 'comprobante_${_meses[cuota.mes]}_${cuota.anio}.pdf',
    );
  }

  void _verComprobantePlataforma(EstadoCuotaPlataforma estado) {
    final path = estado.comprobanteUrl;
    if (path == null) return;
    imprimirArchivoDocumento(
      context: context,
      obtenerUrlFirmada: _servicioPlataforma.obtenerUrlComprobante,
      path: path,
      nombreSugerido: 'comprobante_plataforma.pdf',
    );
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'pagado':
        return AppTheme.estadoOk;
      case 'atrasado':
        return AppTheme.estadoUrgente;
      case 'pendiente':
        return AppTheme.estadoAtencion;
      default:
        return Colors.grey;
    }
  }

  String _labelEstado(String estado) {
    const labels = {
      'pagado': 'Pagado',
      'atrasado': 'Atrasado',
      'pendiente': 'Pendiente',
      'exonerado': 'Exonerado',
    };
    return labels[estado] ?? estado;
  }

  Color _colorEstadoPlataforma(String estado) {
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

  String _labelEstadoPlataforma(String estado) {
    const labels = {
      'pagado': 'Pagado',
      'exonerado': 'Exonerado',
      'pendiente': 'Pendiente',
      'moroso': 'Moroso',
    };
    return labels[estado] ?? estado;
  }

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return Scaffold(
      appBar: AppBar(title: const Text('Mis pagos')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_futurePlataforma != null) ...[
              Text('Cuota de plataforma', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Lo que le pagás a TapePy por el servicio -- distinto de tus pagos internos.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              FutureBuilder<EstadoCuotaPlataforma>(
                future: _futurePlataforma,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!snapshot.hasData) {
                    return Text('No se pudo cargar: ${snapshot.error}');
                  }
                  final estado = snapshot.data!;
                  final color = _colorEstadoPlataforma(estado.estado);
                  final tieneComprobante = estado.comprobanteUrl != null;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        const SizedBox(height: 10),
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
                                    child: Text(_labelEstadoPlataforma(estado.estado),
                                        style:
                                            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                                  ),
                                ],
                              ),
                              if (tieneComprobante || !estado.alDia) ...[
                                const SizedBox(height: 10),
                                if (tieneComprobante)
                                  OutlinedButton.icon(
                                    onPressed: () => _verComprobantePlataforma(estado),
                                    icon: const Icon(Icons.receipt_long_outlined),
                                    label: const Text('Ver comprobante'),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: _reportarPagoPlataforma,
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Reportar pago'),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
            Text('Pagos internos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<CuotaPropia>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final cuotas = snapshot.data ?? [];
                if (cuotas.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
                    child: Column(
                      children: [
                        Icon(Icons.payments_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text('Todavía no hay pagos registrados', textAlign: TextAlign.center),
                      ],
                    ),
                  );
                }
                return Column(
                  children: cuotas.map((cuota) {
                    final color = _colorEstado(cuota.estado);
                    final tieneComprobante = cuota.comprobanteUrl != null;
                    final yaPagado = cuota.estado == 'pagado';
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
                                  IconBadge(icono: Icons.payments_outlined, color: color, diametro: 44),
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
                                        Text('₲ ${formatoMonto.format(cuota.montoTotal)}',
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
                                    child: Text(_labelEstado(cuota.estado),
                                        style:
                                            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
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
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FormularioReportarPago extends StatefulWidget {
  final CuotaPropia cuota;
  final Usuario usuario;
  final ConductorService service;
  const _FormularioReportarPago({
    required this.cuota,
    required this.usuario,
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
    final archivo =
        await ImagePicker().pickImage(source: origen, maxWidth: 1600, imageQuality: 85);
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
    } on CuotaException catch (e) {
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

class _FormularioReportarPagoPlataforma extends StatefulWidget {
  final String usuarioId;
  final String organizacionId;
  final CuotaPlataformaService service;
  const _FormularioReportarPagoPlataforma({
    required this.usuarioId,
    required this.organizacionId,
    required this.service,
  });

  @override
  State<_FormularioReportarPagoPlataforma> createState() => _FormularioReportarPagoPlataformaState();
}

class _FormularioReportarPagoPlataformaState extends State<_FormularioReportarPagoPlataforma> {
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
          Text('Reportar pago de plataforma', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Cuota de plataforma · ${_meses[DateTime.now().month]} ${DateTime.now().year}',
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
