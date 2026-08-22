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
/// (autoservicio, ver [CuotaPlataformaService]). Un solo botón
/// "Registrar pago" (FAB) abre UN formulario -- misma estructura que
/// "Subir documento": un menú desplegable con las opciones reales
/// (plataforma si no está al día, cada cuota interna pendiente/
/// atrasada) y "Otro pago" siempre al final para lo que no esté en la
/// lista, con descripción libre. El monto es SIEMPRE editable ahí
/// mismo, sin importar qué opción se elija. Pedido explícito de Elias
/// (2026-08-22, 2ª vuelta): quería que fuera un solo menú desplegable
/// como en documentos, no un selector aparte que abre un formulario
/// distinto según lo elegido.
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

  /// Abre UN solo formulario -- misma estructura que "Subir documento":
  /// un menú desplegable con las opciones reales -- plataforma si no
  /// está al día, cada cuota interna pendiente/atrasada -- y "Otro
  /// pago" siempre al final para lo que no esté en la lista, con
  /// descripción libre. El monto es SIEMPRE editable ahí mismo, sin
  /// pasos intermedios. Pedido de Elias 2026-08-22 (2ª vuelta): antes
  /// era un selector aparte que abría un formulario distinto según lo
  /// elegido -- quería que fuera un solo menú desplegable, como
  /// documentos.
  Future<void> _abrirFormularioPago(List<_OpcionPago> opciones) async {
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId == null) return;
    final reportado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioRegistrarPago(
        opciones: opciones,
        usuario: widget.usuario,
        service: _service,
        servicioPlataforma: _servicioPlataforma,
      ),
    );
    if (reportado == true) _refrescar();
  }

  /// El botón único del FAB: junta lo que falta pagar (plataforma --
  /// siempre aparece como opción mientras no esté al día, es
  /// obligatoria -- + cada cuota interna pendiente/atrasada) y agrega
  /// "Otro pago" al final para declarar algo con motivo y monto
  /// libres. Todo eso se ofrece como opciones dentro del mismo
  /// formulario, no en un selector aparte.
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
      _OpcionPago.otro(),
    ];

    await _abrirFormularioPago(opciones);
  }

  /// "Reportar pago" tocado directamente desde la tarjeta de una cuota
  /// interna puntual -- abre el mismo formulario, ya con esa cuota
  /// elegida (sin menú, porque ya se sabe cuál es).
  Future<void> _reportarPago(CuotaPropia cuota) => _abrirFormularioPago([_OpcionPago.interna(cuota)]);

  /// Igual que arriba pero para la cuota de plataforma del mes.
  Future<void> _reportarPagoPlataforma(EstadoCuotaPlataforma estado) =>
      _abrirFormularioPago([_OpcionPago.plataforma(estado)]);

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
        foregroundColor: Colors.white,
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
                    final hoy = DateTime.now();
                    // El historial no repite el mes en curso -- ese ya
                    // se muestra en la tarjeta "Este mes" de más abajo,
                    // siempre visible mientras no esté pagado (pedido
                    // de Elias 2026-08-22: la cuota de plataforma es
                    // obligatoria y tiene que quedar ahí como pendiente
                    // hasta que se pague, no escondida atrás del botón).
                    final historialPlataforma = (snapshotHistorialPlataforma.data ?? [])
                        .where((c) => !(c.mes == hoy.month && c.anio == hoy.year))
                        .toList();
                    final tienePlataforma = estadoPlataforma != null;
                    final hayContenidoPlataforma = tienePlataforma || historialPlataforma.isNotEmpty;

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
                          Text('Cuota de plataforma', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (estadoPlataforma != null)
                            Card(
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
                                            color: _colorEstado(estadoPlataforma.estado),
                                            diametro: 44),
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
                                              Text('₲ ${formatoMonto.format(estadoPlataforma.monto)}',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      fontWeight: FontWeight.w600)),
                                              if (estadoPlataforma.alDia && estadoPlataforma.metodoPago != null)
                                                Text('Pagado por: ${_labelMetodo(estadoPlataforma.metodoPago)}',
                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _colorEstado(estadoPlataforma.estado).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(_labelEstado(estadoPlataforma.estado),
                                              style: TextStyle(
                                                  color: _colorEstado(estadoPlataforma.estado),
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (estadoPlataforma.comprobanteUrl != null)
                                      OutlinedButton.icon(
                                        onPressed: () => _verComprobantePlataforma(CuotaPlataformaItem(
                                          id: estadoPlataforma.cuotaId ?? '',
                                          usuarioId: estadoPlataforma.usuarioId,
                                          organizacionId: widget.usuario.organizacionId ?? '',
                                          mes: hoy.month,
                                          anio: hoy.year,
                                          monto: estadoPlataforma.monto,
                                          estado: estadoPlataforma.estado,
                                          motivo: 'Cuota de plataforma',
                                          comprobanteUrl: estadoPlataforma.comprobanteUrl,
                                        )),
                                        icon: const Icon(Icons.receipt_long_outlined),
                                        label: const Text('Ver comprobante'),
                                      )
                                    else if (!estadoPlataforma.alDia)
                                      OutlinedButton.icon(
                                        onPressed: () => _reportarPagoPlataforma(estadoPlataforma!),
                                        icon: const Icon(Icons.check_circle_outline),
                                        label: const Text('Reportar pago'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (historialPlataforma.isNotEmpty) ...[
                            const SizedBox(height: 4),
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

/// Una opción dentro del menú desplegable "¿Qué vas a pagar?" -- ya
/// sea la cuota de plataforma del mes en curso, una cuota interna
/// pendiente/atrasada puntual, o "Otro pago" (siempre al final).
class _OpcionPago {
  final String titulo;
  final bool esPlataforma;
  final bool esOtro;
  final CuotaPropia? cuota;
  final double? montoSugerido;

  _OpcionPago.plataforma(EstadoCuotaPlataforma estado)
      : titulo = 'Pago a plataforma',
        esPlataforma = true,
        esOtro = false,
        cuota = null,
        montoSugerido = estado.monto;

  _OpcionPago.interna(CuotaPropia c)
      : titulo = c.motivo,
        esPlataforma = false,
        esOtro = false,
        cuota = c,
        montoSugerido = c.montoTotal;

  _OpcionPago.otro()
      : titulo = 'Otro pago',
        esPlataforma = false,
        esOtro = true,
        cuota = null,
        montoSugerido = null;
}

/// Formulario único para registrar cualquier pago -- misma estructura
/// que "Subir documento" (un menú desplegable con las opciones reales
/// y "Otro" al final, todo en una sola pantalla). Pedido de Elias
/// 2026-08-22 (2ª vuelta): no quería un selector aparte que abriera un
/// formulario distinto según lo elegido, sino UN menú desplegable con
/// las opciones (que sí tienen que aparecer -- plataforma, cuotas ya
/// generadas por el presidente) y el monto siempre editable ahí
/// mismo, sin que ninguna opción imponga un monto fijo.
class _FormularioRegistrarPago extends StatefulWidget {
  final List<_OpcionPago> opciones;
  final Usuario usuario;
  final ConductorService service;
  final CuotaPlataformaService servicioPlataforma;
  const _FormularioRegistrarPago({
    required this.opciones,
    required this.usuario,
    required this.service,
    required this.servicioPlataforma,
  });

  @override
  State<_FormularioRegistrarPago> createState() => _FormularioRegistrarPagoState();
}

class _FormularioRegistrarPagoState extends State<_FormularioRegistrarPago> {
  late _OpcionPago _seleccionada;
  late final TextEditingController _montoController;
  final _motivoLibreController = TextEditingController();
  String _metodo = 'efectivo';
  XFile? _archivo;
  DateTime _fechaPago = DateTime.now();
  bool _subiendo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _seleccionada = widget.opciones.first;
    _montoController = TextEditingController(text: _textoMonto(_seleccionada));
  }

  @override
  void dispose() {
    _montoController.dispose();
    _motivoLibreController.dispose();
    super.dispose();
  }

  String _textoMonto(_OpcionPago opcion) {
    final monto = opcion.montoSugerido;
    return monto != null ? NumberFormat.decimalPattern('es').format(monto) : '';
  }

  void _seleccionar(_OpcionPago? opcion) {
    if (opcion == null) return;
    setState(() {
      _seleccionada = opcion;
      _montoController.text = _textoMonto(opcion);
      _error = null;
    });
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
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId == null) return;
    final monto = double.tryParse(_montoController.text.trim().replaceAll('.', '').replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Ingresá un monto válido.');
      return;
    }
    String motivoLibre = '';
    if (_seleccionada.esOtro) {
      motivoLibre = _motivoLibreController.text.trim();
      if (motivoLibre.isEmpty) {
        setState(() => _error = 'Contá qué estás pagando.');
        return;
      }
    }
    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      final bytes = _archivo != null ? await _archivo!.readAsBytes() : null;
      final extension = _archivo != null ? _archivo!.name.split('.').last : null;
      if (_seleccionada.esPlataforma) {
        await widget.servicioPlataforma.reportarPago(
          usuarioId: widget.usuario.id,
          organizacionId: organizacionId,
          monto: monto,
          metodoPago: _metodo,
          fechaPago: _fechaPago,
          bytes: bytes,
          extension: extension,
        );
      } else if (_seleccionada.esOtro) {
        await widget.service.crearPagoPropio(
          organizacionId: organizacionId,
          usuarioId: widget.usuario.id,
          motivo: motivoLibre,
          montoBase: monto,
          metodoPago: _metodo,
          fechaPago: _fechaPago,
          bytes: bytes,
          extension: extension,
        );
      } else {
        await widget.service.reportarPago(
          cuotaId: _seleccionada.cuota!.id,
          usuarioId: widget.usuario.id,
          organizacionId: organizacionId,
          monto: monto,
          metodoPago: _metodo,
          fechaPago: _fechaPago,
          bytes: bytes,
          extension: extension,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CuotaException catch (e) {
      setState(() => _error = e.message);
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
          Text('Registrar pago', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (widget.opciones.length > 1)
            DropdownButtonFormField<_OpcionPago>(
              value: _seleccionada,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '¿Qué vas a pagar?', border: OutlineInputBorder()),
              items: widget.opciones
                  .map((o) => DropdownMenuItem(value: o, child: Text(o.titulo, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _seleccionar,
            )
          else
            Text(
              'Vas a pagar: ${_seleccionada.titulo}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          if (_seleccionada.esOtro) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _motivoLibreController,
              decoration: const InputDecoration(
                labelText: 'Descripción del pago',
                hintText: 'Ej: Multa, evento, aporte extra',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _montoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monto (₲)', border: OutlineInputBorder()),
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
              label: Text(_archivo == null ? 'Elegir foto del comprobante (opcional)' : 'Foto seleccionada ✓'),
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
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.rojoInstitucional,
              foregroundColor: Colors.white,
            ),
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

