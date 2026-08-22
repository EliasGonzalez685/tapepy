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

/// Pantalla única de "Mis pagos": junta las cuotas internas (las carga
/// el presidente, ver [CuotaPropia]) y la cuota de plataforma
/// (autoservicio, ver [CuotaPlataformaService]) -- pero SIN un botón de
/// "Reportar pago" separado para cada una. Un solo botón "Registrar
/// pago" (FAB) abre un selector con las opciones pendientes (ej. "Pago
/// a plataforma", o cada cuota interna por motivo/mes) y de ahí sigue
/// el mismo formulario de siempre (método efectivo/transferencia +
/// comprobante si corresponde). Pedido explícito de Elias
/// (2026-08-22): quería el botón único con opciones "como ya existía
/// antes", no una sección aparte para cada cosa.
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
  Future<List<CuotaPlataformaItem>>? _historialPlataformaFuture;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _service.cargarCuotas(widget.usuario.id);
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId != null) {
      _futurePlataforma = _servicioPlataforma.cargarMiEstado(
        usuarioId: widget.usuario.id,
        organizacionId: organizacionId,
      );
      _historialPlataformaFuture = _servicioPlataforma.cargarMia(widget.usuario.id);
    }
  }

  void _refrescar() => setState(_cargar);

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

  /// El botón único: junta lo que falta pagar (plataforma, si no está
  /// al día este mes, + cada cuota interna pendiente/atrasada) y deja
  /// elegir cuál se está reportando.
  Future<void> _elegirQuePagar() async {
    List<CuotaPropia> pendientesInternas = [];
    try {
      final cuotas = await _future;
      pendientesInternas = cuotas.where((c) => c.estado == 'pendiente' || c.estado == 'atrasado').toList();
    } catch (_) {}

    EstadoCuotaPlataforma? estadoPlataforma;
    if (_futurePlataforma != null) {
      try {
        estadoPlataforma = await _futurePlataforma;
      } catch (_) {}
    }

    if (!mounted) return;

    final opciones = <_OpcionPago>[
      if (estadoPlataforma != null && !estadoPlataforma.alDia) _OpcionPago.plataforma(estadoPlataforma),
      ...pendientesInternas.map(_OpcionPago.interna),
    ];

    if (opciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estás al día con todos tus pagos.')),
      );
      return;
    }

    final elegida = await showModalBottomSheet<_OpcionPago>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _SelectorPagoSheet(opciones: opciones),
    );
    if (elegida == null) return;
    if (elegida.esPlataforma) {
      await _reportarPagoPlataforma();
    } else {
      await _reportarPago(elegida.cuota!);
    }
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

  void _verComprobantePlataforma(CuotaPlataformaItem c) {
    final path = c.comprobanteUrl;
    if (path == null) return;
    imprimirArchivoDocumento(
      context: context,
      obtenerUrlFirmada: _servicioPlataforma.obtenerUrlComprobante,
      path: path,
      nombreSugerido: 'comprobante_plataforma_${_meses[c.mes]}_${c.anio}.pdf',
    );
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'pagado':
      case 'exonerado':
        return AppTheme.estadoOk;
      case 'atrasado':
      case 'moroso':
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
      'moroso': 'Moroso',
    };
    return labels[estado] ?? estado;
  }

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return Scaffold(
      appBar: AppBar(title: const Text('Mis pagos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _elegirQuePagar,
        backgroundColor: AppTheme.rojoInstitucional,
        icon: const Icon(Icons.add),
        label: const Text('Registrar pago'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refrescar();
          await _future;
        },
        child: FutureBuilder<List<CuotaPropia>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final cuotas = snapshot.data ?? [];

            return FutureBuilder<EstadoCuotaPlataforma?>(
              future: _futurePlataforma,
              builder: (context, snapshotPlataforma) {
                final estadoPlataforma = snapshotPlataforma.data;
                return FutureBuilder<List<CuotaPlataformaItem>>(
                  future: _historialPlataformaFuture,
                  builder: (context, snapshotHistorialPlataforma) {
                    final historialPlataforma = snapshotHistorialPlataforma.data ?? [];
                    final hayContenidoPlataforma =
                        (estadoPlataforma?.enDeuda ?? false) || historialPlataforma.isNotEmpty;

                    if (cuotas.isEmpty && !hayContenidoPlataforma) {
                      return ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                            child: Column(
                              children: [
                                Icon(Icons.payments_outlined,
                                    size: 48, color: Theme.of(context).colorScheme.outline),
                                const SizedBox(height: 12),
                                const Text('Todavía no hay pagos registrados', textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (hayContenidoPlataforma) ...[
                          if (estadoPlataforma?.enDeuda ?? false) ...[
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
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.estadoUrgente,
                                          fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (historialPlataforma.isNotEmpty) ...[
                            Text('Cuota de plataforma', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            ...historialPlataforma.map((c) {
                              final color = _colorEstado(c.estado);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          IconBadge(
                                              icono: Icons.workspace_premium_outlined,
                                              color: color,
                                              diametro: 44),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${_meses[c.mes]} ${c.anio}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                                Text('₲ ${formatoMonto.format(c.monto)}',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                        fontWeight: FontWeight.w600)),
                                                if (c.alDia && c.metodoPago != null)
                                                  Text('Pagado por: ${_labelMetodo(c.metodoPago)}',
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color:
                                                              Theme.of(context).colorScheme.onSurfaceVariant)),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(_labelEstado(c.estado),
                                                style: TextStyle(
                                                    color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                      if (c.comprobanteUrl != null) ...[
                                        const SizedBox(height: 10),
                                        OutlinedButton.icon(
                                          onPressed: () => _verComprobantePlataforma(c),
                                          icon: const Icon(Icons.receipt_long_outlined),
                                          label: const Text('Ver comprobante'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 20),
                          ],
                        ],
                        if (cuotas.isNotEmpty) ...[
                          if (hayContenidoPlataforma) ...[
                            Text('Pagos internos', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                          ],
                          ...cuotas.map((cuota) {
                            final color = _colorEstado(cuota.estado);
                            final tieneComprobante = cuota.comprobanteUrl != null;
                            final yaPagado = cuota.estado == 'pagado';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
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
                                              style: TextStyle(
                                                  color: color, fontWeight: FontWeight.w600, fontSize: 12)),
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
                            );
                          }),
                        ],
                        // Espacio para que el FAB no tape la última tarjeta.
                        const SizedBox(height: 72),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Una opción dentro del selector "¿Qué pago vas a registrar?" -- ya
/// sea la cuota de plataforma del mes en curso o una cuota interna
/// pendiente/atrasada puntual.
class _OpcionPago {
  final String titulo;
  final String subtitulo;
  final bool esPlataforma;
  final CuotaPropia? cuota;

  _OpcionPago.plataforma(EstadoCuotaPlataforma estado)
      : titulo = 'Pago a plataforma',
        subtitulo = '₲ ${NumberFormat.decimalPattern('es').format(estado.monto)} · este mes',
        esPlataforma = true,
        cuota = null;

  _OpcionPago.interna(CuotaPropia c)
      : titulo = c.motivo,
        subtitulo = '₲ ${NumberFormat.decimalPattern('es').format(c.montoTotal)} · ${_meses[c.mes]} ${c.anio}',
        esPlataforma = false,
        cuota = c;
}

class _SelectorPagoSheet extends StatelessWidget {
  final List<_OpcionPago> opciones;
  const _SelectorPagoSheet({required this.opciones});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text('¿Qué pago vas a registrar?', style: Theme.of(context).textTheme.titleLarge),
          ),
          ...opciones.map((o) => ListTile(
                leading: Icon(
                  o.esPlataforma ? Icons.workspace_premium_outlined : Icons.payments_outlined,
                  color: AppTheme.rojoInstitucional,
                ),
                title: Text(o.titulo),
                subtitle: Text(o.subtitulo),
                onTap: () => Navigator.of(context).pop(o),
              )),
          const SizedBox(height: 8),
        ],
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
          Text('Reportar pago', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Pago a plataforma',
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
