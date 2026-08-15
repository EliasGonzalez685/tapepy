import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/utils/imprimir_documento.dart';
import '../../../shared/widgets/badge_en_servicio.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../../shared/widgets/vehiculos_conductor_sheet.dart';
import '../data/lote_pago_service.dart';
import '../data/parada_detalle_service.dart';
import '../data/parada_resumen.dart';
import 'balance_pagos_screen.dart';
import 'cuota_form_widgets.dart';
import 'incidente_form_widget.dart';
import 'lote_pago_form_widget.dart';

/// Detalle de una parada: conductores, cuotas, documentos e incidentes.
/// Navegación por una barra de íconos horizontal (en vez de un TabBar
/// genérico) para que se sienta parte del mismo lenguaje visual que el
/// resto de la app (IconBadge, colores de estado).
class ParadaDetalleScreen extends StatefulWidget {
  final ParadaResumen parada;
  final Usuario? usuario;
  const ParadaDetalleScreen({super.key, required this.parada, this.usuario});

  @override
  State<ParadaDetalleScreen> createState() => _ParadaDetalleScreenState();
}

enum _Seccion { conductores, cuotas, documentos, incidentes }

class _ParadaDetalleScreenState extends State<ParadaDetalleScreen> {
  final _service = ParadaDetalleService();
  final _lotePagoService = LotePagoService();
  _Seccion _seccion = _Seccion.conductores;

  bool get _esDuenoPlataforma => widget.usuario?.rol == UserRole.duenoPlataforma;

  late Future<Map<String, dynamic>> _paradaFuture;
  late Future<List<ConductorItem>> _conductoresFuture;
  late Future<List<CuotaItem>> _cuotasFuture;
  late Future<List<DocumentoItem>> _documentosFuture;
  late Future<List<IncidenteItem>> _incidentesFuture;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  void _cargarTodo() {
    _paradaFuture = _service.cargarParada(widget.parada.id);
    _conductoresFuture = _service.cargarConductores(widget.parada.id);
    _cuotasFuture = _service.cargarCuotas(widget.parada.id);
    _documentosFuture = _service.cargarDocumentos(widget.parada.id);
    _incidentesFuture = _service.cargarIncidentes(widget.parada.id);
  }

  Future<void> _refrescar() async {
    setState(_cargarTodo);
    await Future.wait([
      _paradaFuture,
      _conductoresFuture,
      _cuotasFuture,
      _documentosFuture,
      _incidentesFuture,
    ]);
  }

  Future<void> _eliminarConductor(ConductorItem conductor) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar conductor'),
        content: Text(
          '¿Eliminar la cuenta de "${conductor.nombre}"? Se borran también su vehículo, '
          'documentos y pagos. Esta acción no se puede deshacer.',
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
      await _service.eliminarConductor(conductor.usuarioId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Se eliminó a ${conductor.nombre}')));
      _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo eliminar. Intentá de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.parada.estado;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.parada.nombre, overflow: TextOverflow.ellipsis, maxLines: 1)),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EncabezadoParada(parada: widget.parada, futureUbicacion: _paradaFuture),
            const SizedBox(height: 18),
            _BarraSecciones(
              seleccion: _seccion,
              onSeleccionar: (s) => setState(() => _seccion = s),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _contenidoSeccion(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      // Conductores y Documentos son de solo lectura para el presidente:
      // cada conductor se registra y sube sus propios documentos, el
      // presidente solo supervisa. El FAB de acción solo aparece en las
      // secciones donde el presidente sí actúa (cuotas, incidentes).
      floatingActionButton: _tituloAccion(_seccion) == null
          ? null
          : FloatingActionButton.extended(
              key: ValueKey('fab_${_seccion.name}'),
              onPressed: () => _onAccion(_seccion),
              backgroundColor: estado.color,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(_tituloAccion(_seccion)!, style: const TextStyle(color: Colors.white)),
            ),
    );
  }

  void _onAccion(_Seccion seccion) {
    switch (seccion) {
      case _Seccion.cuotas:
        _elegirTipoPago();
        break;
      case _Seccion.incidentes:
        _reportarIncidente();
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_tituloAccion(seccion)} — próximamente')),
        );
    }
  }

  Future<void> _reportarIncidente() async {
    final usuario = widget.usuario;
    final organizacionId = usuario?.organizacionId;
    if (usuario == null || organizacionId == null) return;
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FormularioIncidenteSheet(
        organizacionId: organizacionId,
        paradaId: widget.parada.id,
        reportadoPor: usuario.id,
        conductoresFuture: _conductoresFuture,
        service: _service,
      ),
    );
    if (creado == true) _refrescar();
  }

  Future<void> _elegirTipoPago() async {
    final opcion = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline, color: AppTheme.rojoInstitucional),
              title: const Text('Pago individual'),
              subtitle: const Text('Para un conductor puntual'),
              onTap: () => Navigator.of(context).pop('individual'),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined, color: AppTheme.rojoInstitucional),
              title: const Text('Pago a todos'),
              subtitle: const Text('Le aparece como pendiente a todos los socios del alcance elegido'),
              onTap: () => Navigator.of(context).pop('todos'),
            ),
          ],
        ),
      ),
    );
    if (opcion == 'individual') {
      _registrarCuota();
    } else if (opcion == 'todos') {
      _generarPagoATodos();
    }
  }

  Future<void> _generarPagoATodos() async {
    final usuario = widget.usuario;
    final organizacionId = usuario?.organizacionId;
    if (usuario == null || organizacionId == null) return;
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FormularioLotePagoSheet(
        organizacionId: organizacionId,
        creadoPor: usuario.id,
        service: _lotePagoService,
        esPresidenteAsociacion: true,
        alcanceInicialId: widget.parada.id,
      ),
    );
    if (creado == true) _refrescar();
  }

  Future<void> _registrarCuota() async {
    final usuario = widget.usuario;
    final organizacionId = usuario?.organizacionId;
    if (usuario == null || organizacionId == null) return;
    final creada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FormularioCuotaSheet(
        organizacionId: organizacionId,
        paradaId: widget.parada.id,
        registradoPor: usuario.id,
        conductoresFuture: _conductoresFuture,
        service: _service,
      ),
    );
    if (creada == true) _refrescar();
  }

  Future<void> _cambiarEstadoCuota(CuotaItem cuota) async {
    final cambiado = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => CambiarEstadoCuotaSheet(cuota: cuota, service: _service),
    );
    if (cambiado == true) _refrescar();
  }

  void _abrirBalancePagos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BalancePagosScreen(
          paradaId: widget.parada.id,
          paradaNombre: widget.parada.nombre,
          service: _service,
        ),
      ),
    );
  }

  String? _tituloAccion(_Seccion s) {
    switch (s) {
      case _Seccion.conductores:
        return null; // solo lectura: cada conductor se registra a sí mismo
      case _Seccion.cuotas:
        // El dueño de plataforma ve todo el control de pagos pero no
        // puede intervenir — sin FAB en esta sección para él.
        return _esDuenoPlataforma ? null : 'Nuevo pago';
      case _Seccion.documentos:
        return null; // solo lectura: cada conductor sube sus propios documentos
      case _Seccion.incidentes:
        return 'Reportar incidente';
    }
  }

  Widget _contenidoSeccion() {
    switch (_seccion) {
      case _Seccion.conductores:
        return Column(
          key: const ValueKey('conductores'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Miembros activos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const _AvisoSoloLectura(
              texto: 'Cada conductor se registra y completa su propio perfil, y prende o '
                  'apaga su propia bandera de "en servicio". Acá solo consultás.',
            ),
            const SizedBox(height: 12),
            _SeccionConductores(
                future: _conductoresFuture, onEliminar: _eliminarConductor, service: _service),
          ],
        );
      case _Seccion.cuotas:
        return Column(
          key: const ValueKey('cuotas'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_esDuenoPlataforma) ...[
              const _AvisoSoloLectura(
                texto: 'Como dueño de plataforma ves todo el control de pagos, pero '
                    'no podés registrar ni modificar pagos — eso es trabajo de la asociación.',
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _abrirBalancePagos,
                icon: const Icon(Icons.bar_chart_outlined),
                label: const Text('Ver balance de pagos'),
              ),
            ),
            const SizedBox(height: 8),
            _SeccionCuotas(
              future: _cuotasFuture,
              onTap: _esDuenoPlataforma ? null : _cambiarEstadoCuota,
            ),
          ],
        );
      case _Seccion.documentos:
        return Column(
          key: const ValueKey('documentos'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AvisoSoloLectura(
              texto: 'Cada conductor sube sus propios documentos y es responsable '
                  'de lo que falte. Tocá un documento para abrirlo o imprimirlo.',
            ),
            const SizedBox(height: 12),
            _SeccionDocumentos(future: _documentosFuture, service: _service),
          ],
        );
      case _Seccion.incidentes:
        return _SeccionIncidentes(key: const ValueKey('incidentes'), future: _incidentesFuture);
    }
  }
}

class _AvisoSoloLectura extends StatelessWidget {
  final String texto;
  const _AvisoSoloLectura({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_outlined,
              size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _EncabezadoParada extends StatelessWidget {
  final ParadaResumen parada;
  final Future<Map<String, dynamic>> futureUbicacion;
  const _EncabezadoParada({required this.parada, required this.futureUbicacion});

  @override
  Widget build(BuildContext context) {
    final estado = parada.estado;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.rojoInstitucional, AppTheme.rojoInstitucional.withValues(alpha: 0.82)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(icono: Icons.location_pin, color: Colors.white24, diametro: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parada.nombre,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    FutureBuilder<Map<String, dynamic>>(
                      future: futureUbicacion,
                      builder: (context, snapshot) {
                        final ubicacion = snapshot.data?['ubicacion'] as String?;
                        if (ubicacion == null || ubicacion.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            ubicacion,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  estado.etiqueta,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(valor: '${parada.conductoresCount}', etiqueta: 'Conductores'),
              _MiniStat(valor: '${parada.cuotasAtrasadasCount}', etiqueta: 'Atrasados'),
              _MiniStat(valor: '${parada.docsPorVencerCount}', etiqueta: 'Docs x vencer'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String valor;
  final String etiqueta;
  const _MiniStat({required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(valor,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
          Text(etiqueta,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        ],
      ),
    );
  }
}

/// Barra horizontal de íconos — el "menú" de secciones del detalle.
class _BarraSecciones extends StatelessWidget {
  final _Seccion seleccion;
  final ValueChanged<_Seccion> onSeleccionar;
  const _BarraSecciones({required this.seleccion, required this.onSeleccionar});

  @override
  Widget build(BuildContext context) {
    final items = [
      (_Seccion.conductores, Icons.groups_outlined, 'Miembros'),
      (_Seccion.cuotas, Icons.payments_outlined, 'Pagos'),
      (_Seccion.documentos, Icons.description_outlined, 'Documentos'),
      (_Seccion.incidentes, Icons.report_gmailerrorred_outlined, 'Incidentes'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: items.map((item) {
        final (seccion, icono, etiqueta) = item;
        final activo = seccion == seleccion;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSeleccionar(seccion),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: activo ? AppTheme.rojoInstitucional.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  IconBadge(
                    icono: icono,
                    color: activo ? AppTheme.rojoInstitucional : Colors.grey.shade300,
                    diametro: 46,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    etiqueta,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                      color: activo ? AppTheme.rojoInstitucional : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// ---------------------------------------------------------------------
/// Secciones
/// ---------------------------------------------------------------------

class _SeccionConductores extends StatelessWidget {
  final Future<List<ConductorItem>> future;
  final void Function(ConductorItem) onEliminar;
  final ParadaDetalleService service;
  const _SeccionConductores({
    super.key,
    required this.future,
    required this.onEliminar,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return _ListaAsync<ConductorItem>(
      future: future,
      vacioIcono: Icons.groups_outlined,
      vacioTexto: 'Todavía no hay conductores en esta parada',
      itemBuilder: (item) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => mostrarVehiculosConductorSheet(
            context,
            conductorId: item.id,
            nombreConductor: item.nombre,
            service: service,
          ),
          child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const IconBadge(icono: Icons.person, color: AppTheme.rojoInstitucional, diametro: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombre,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (item.turno != null) _turnoLabel(item.turno!),
                        if (item.vehiculoDescripcion != null) item.vehiculoDescripcion!,
                        if (item.chapa != null) item.chapa!,
                      ].join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    if (item.resolucionNumero != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Resolución Nº ${item.resolucionNumero}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              BadgeEnServicio(enServicio: item.enServicio),
              const SizedBox(width: 4),
              if (item.telefono != null)
                Icon(Icons.phone_outlined, color: Theme.of(context).colorScheme.outline, size: 20),
              IconButton(
                icon: Icon(Icons.person_remove_outlined, color: Theme.of(context).colorScheme.error),
                tooltip: 'Eliminar conductor',
                onPressed: () => onEliminar(item),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  static String _turnoLabel(String turno) {
    const labels = {
      'manana': 'Mañana',
      'tarde': 'Tarde',
      'noche': 'Noche',
      'completo': 'Completo',
    };
    return labels[turno] ?? turno;
  }
}

class _SeccionCuotas extends StatelessWidget {
  final Future<List<CuotaItem>> future;
  final void Function(CuotaItem)? onTap;
  const _SeccionCuotas({super.key, required this.future, required this.onTap});

  static const _meses = [
    '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
  ];

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

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return _ListaAsync<CuotaItem>(
      future: future,
      vacioIcono: Icons.payments_outlined,
      vacioTexto: 'Todavía no hay pagos registrados',
      itemBuilder: (item) {
        final color = _colorEstado(item.estado);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap == null ? null : () => onTap!(item),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  IconBadge(icono: Icons.payments_outlined, color: color, diametro: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.usuarioNombre,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(item.motivo,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text(
                          '${_meses[item.mes]} ${item.anio} · ₲ ${formatoMonto.format(item.montoTotal)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _labelEstado(item.estado),
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeccionDocumentos extends StatelessWidget {
  final Future<List<DocumentoItem>> future;
  final ParadaDetalleService service;
  const _SeccionDocumentos({super.key, required this.future, required this.service});

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

  String _labelTipo(String tipo) {
    const labels = {
      'cedula': 'Cédula',
      'licencia_conducir': 'Licencia de conducir',
      'antecedentes_policiales': 'Antecedentes policiales',
      'seguro_vehicular': 'Seguro vehicular',
      'revision_tecnica': 'Revisión técnica',
      'carta_verde': 'Carta verde',
      'habilitacion_vehicular': 'Habilitación vehicular',
      'cedula_verde': 'Cédula verde',
      'habilitacion_municipal': 'Habilitación municipal',
      'otro': 'Otro documento',
    };
    return labels[tipo] ?? tipo;
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return _ListaAsync<DocumentoItem>(
      future: future,
      vacioIcono: Icons.description_outlined,
      vacioTexto: 'No hay documentos por revisar en esta parada',
      itemBuilder: (item) {
        final color = _colorEstado(item.estado);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => imprimirArchivoDocumento(
              context: context,
              obtenerUrlFirmada: service.obtenerUrlFirmada,
              path: item.archivoUrl,
              nombreSugerido: item.nombreArchivo ?? '${_labelTipo(item.tipo)}.pdf',
            ),
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
                        Text('${item.entidad} · ${_labelTipo(item.tipo)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (item.fechaVencimiento != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Vence ${formatoFecha.format(item.fechaVencimiento!)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _labelEstado(item.estado),
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.print_outlined, color: Theme.of(context).colorScheme.outline, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeccionIncidentes extends StatelessWidget {
  final Future<List<IncidenteItem>> future;
  const _SeccionIncidentes({super.key, required this.future});

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'abierto':
        return AppTheme.estadoUrgente;
      case 'en_revision':
        return AppTheme.estadoAtencion;
      case 'resuelto':
        return AppTheme.estadoOk;
      default:
        return Colors.grey;
    }
  }

  String _labelEstado(String estado) {
    const labels = {'abierto': 'Abierto', 'en_revision': 'En revisión', 'resuelto': 'Resuelto'};
    return labels[estado] ?? estado;
  }

  String _labelTipo(String tipo) {
    const labels = {
      'accidente': 'Accidente',
      'mecanico': 'Falla mecánica',
      'conflicto': 'Conflicto',
      'otro': 'Otro',
    };
    return labels[tipo] ?? tipo;
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return _ListaAsync<IncidenteItem>(
      future: future,
      vacioIcono: Icons.report_gmailerrorred_outlined,
      vacioTexto: 'No hay incidentes reportados en esta parada',
      itemBuilder: (item) {
        final color = _colorEstado(item.estado);
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(icono: Icons.report_gmailerrorred_outlined, color: color, diametro: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_labelTipo(item.tipo),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(item.descripcion, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        formatoFecha.format(item.creadoEn),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _labelEstado(item.estado),
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Widget genérico: carga, vacío o lista — reutilizado por las 4 secciones.
class _ListaAsync<T> extends StatelessWidget {
  final Future<List<T>> future;
  final Widget Function(T item) itemBuilder;
  final IconData vacioIcono;
  final String vacioTexto;

  const _ListaAsync({
    super.key,
    required this.future,
    required this.itemBuilder,
    required this.vacioIcono,
    required this.vacioTexto,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No se pudo cargar: ${snapshot.error}')),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(vacioIcono, size: 40, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(vacioTexto, textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        return Column(children: items.map(itemBuilder).toList());
      },
    );
  }
}
