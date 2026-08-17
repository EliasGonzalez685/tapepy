import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/utils/imprimir_documento.dart';
import '../../../shared/widgets/badge_en_servicio.dart';
import '../../../shared/widgets/en_servicio_switch.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../../shared/widgets/menu_lateral.dart';
import '../../../shared/widgets/vehiculos_conductor_sheet.dart';
import '../../asociacion/data/parada_detalle_service.dart';
import '../../asociacion/data/parada_resumen.dart';
import '../../asociacion/presentation/balance_pagos_screen.dart';
import '../../asociacion/presentation/cuota_form_widgets.dart';
import '../../asociacion/presentation/imprimir_listado_screen.dart';
import '../../asociacion/presentation/incidente_form_widget.dart';
import '../../asociacion/data/lote_pago_service.dart';
import '../../asociacion/presentation/lote_pago_form_widget.dart';
import '../../conductor/presentation/mi_perfil_socio_screen.dart';
import '../../asociacion/presentation/solicitudes_pendientes_screen.dart';
import '../../asociacion/presentation/vencimientos_carnet_screen.dart';
import '../../auth/data/auth_service.dart';
import '../../firma/data/firma_service.dart';
import '../../firma/presentation/mi_firma_screen.dart';
import '../../mensajeria/data/mensajeria_service.dart';
import '../data/parada_presidente_service.dart';

enum _Seccion { conductores, cuotas, documentos, incidentes, convenios }

const _tiposDocumentoParada = {
  'habilitacion_municipal': 'Habilitación municipal',
  'otro': 'Otro documento',
};

/// Home del rol presidente de parada: su propia parada — conductores y
/// cuotas/incidentes de solo consulta (mismo criterio que el panel de
/// asociación), documentos DE LA PARADA (esos sí los sube él, o el
/// presidente de asociación) y convenios de publicidad con empresas.
class ParadaHomeScreen extends StatefulWidget {
  final Usuario? usuario;
  const ParadaHomeScreen({super.key, this.usuario});

  @override
  State<ParadaHomeScreen> createState() => _ParadaHomeScreenState();
}

class _ParadaHomeScreenState extends State<ParadaHomeScreen> {
  final _presidenteService = ParadaPresidenteService();
  final _detalleService = ParadaDetalleService();
  final _lotePagoService = LotePagoService();
  final _mensajeriaService = MensajeriaService();
  final _firmaService = FirmaService();
  final _organizacionService = OrganizacionService();

  _Seccion _seccion = _Seccion.conductores;
  bool _cargandoParada = true;
  MiParadaInfo? _parada;
  int? _solicitudesPendientesCount;
  int? _solicitudesFirmaCount;
  String? _organizacionNombre;

  int get _totalSolicitudesPendientes =>
      (_solicitudesPendientesCount ?? 0) + (_solicitudesFirmaCount ?? 0);

  late Future<int> _noLeidosFuture;
  Future<ParadaResumen>? _resumenFuture;
  Future<List<ConductorItem>>? _conductoresFuture;
  Future<List<CuotaItem>>? _cuotasFuture;
  Future<List<DocumentoItem>>? _documentosFuture;
  Future<List<IncidenteItem>>? _incidentesFuture;
  Future<List<ConvenioItem>>? _conveniosFuture;

  @override
  void initState() {
    super.initState();
    _cargarInicial();
    _cargarSolicitudesFirma();
    _cargarOrganizacion();
  }

  Future<void> _cargarOrganizacion() async {
    final organizacionId = widget.usuario?.organizacionId;
    if (organizacionId == null) return;
    try {
      final nombre = await _organizacionService.cargarNombre(organizacionId);
      if (!mounted) return;
      setState(() => _organizacionNombre = nombre);
    } catch (_) {
      // Silencioso: si falla, el AppBar se queda con el nombre por defecto.
    }
  }

  void _cargarInicial() {
    final id = widget.usuario?.id;
    _cargandoParada = true;
    _noLeidosFuture = id == null ? Future.value(0) : _mensajeriaService.contarNoLeidos(id);
    final future = id == null ? Future.value(null) : _presidenteService.cargarMiParada(id);
    future.then((parada) {
      if (!mounted) return;
      setState(() {
        _parada = parada;
        _cargandoParada = false;
        if (parada != null) _cargarSecciones(parada.id);
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _cargandoParada = false);
    });
  }

  void _cargarSecciones(String paradaId) {
    _resumenFuture = _presidenteService.cargarResumenParada(paradaId);
    _conductoresFuture = _detalleService.cargarConductores(paradaId);
    _cuotasFuture = _detalleService.cargarCuotas(paradaId);
    _documentosFuture = _detalleService.cargarDocumentos(paradaId);
    _incidentesFuture = _detalleService.cargarIncidentes(paradaId);
    _conveniosFuture = _presidenteService.cargarConvenios(paradaId);
    _cargarSolicitudesPendientes(paradaId);
  }

  Future<void> _cargarSolicitudesPendientes(String paradaId) async {
    try {
      final lista = await _detalleService.cargarSolicitudesPendientes(paradaId);
      if (!mounted) return;
      setState(() => _solicitudesPendientesCount = lista.length);
    } catch (_) {
      // Silencioso: el badge es solo un aviso, no bloquea nada si falla.
    }
  }

  Future<void> _cargarSolicitudesFirma() async {
    final id = widget.usuario?.id;
    if (id == null) return;
    try {
      final lista = await _firmaService.cargarSolicitudesPendientes(id);
      if (!mounted) return;
      setState(() => _solicitudesFirmaCount = lista.length);
    } catch (_) {
      // Silencioso: el badge es solo un aviso, no bloquea nada si falla.
    }
  }

  Future<void> _refrescar() async {
    _cargarSolicitudesFirma();
    if (_parada == null) {
      setState(_cargarInicial);
      return;
    }
    setState(() => _cargarSecciones(_parada!.id));
    await Future.wait([
      _resumenFuture!,
      _conductoresFuture!,
      _cuotasFuture!,
      _documentosFuture!,
      _incidentesFuture!,
      _conveniosFuture!,
    ]);
  }

  Future<void> _cerrarSesion() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRouter.login, (route) => false);
  }

  Future<void> _subirDocumentoParada() async {
    final parada = _parada;
    final usuarioId = widget.usuario?.id;
    if (parada == null || usuarioId == null) return;
    final subido = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioDocumentoParada(
        organizacionId: parada.organizacionId,
        paradaId: parada.id,
        usuarioId: usuarioId,
        service: _presidenteService,
      ),
    );
    if (subido == true) _refrescar();
  }

  Future<void> _nuevoConvenio() async {
    final parada = _parada;
    final usuarioId = widget.usuario?.id;
    if (parada == null || usuarioId == null) return;
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioConvenio(
        organizacionId: parada.organizacionId,
        paradaId: parada.id,
        usuarioId: usuarioId,
        service: _presidenteService,
      ),
    );
    if (creado == true) _refrescar();
  }

  Future<void> _eliminarConvenio(ConvenioItem convenio) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar convenio'),
        content: Text('¿Eliminar el convenio con "${convenio.empresaNombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Eliminar', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _presidenteService.eliminarConvenio(convenio.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Convenio eliminado')));
      _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo eliminar. Intentá de nuevo.')));
    }
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
      await _detalleService.eliminarConductor(conductor.usuarioId);
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

  String? _tituloAccion(_Seccion s) {
    switch (s) {
      case _Seccion.conductores:
        return null; // solo lectura: cada conductor se registra a sí mismo
      case _Seccion.cuotas:
        return 'Nuevo pago';
      case _Seccion.documentos:
        return 'Subir documento de la parada';
      case _Seccion.incidentes:
        return 'Reportar incidente';
      case _Seccion.convenios:
        return 'Nuevo convenio';
    }
  }

  void _onAccion() {
    switch (_seccion) {
      case _Seccion.documentos:
        _subirDocumentoParada();
        break;
      case _Seccion.convenios:
        _nuevoConvenio();
        break;
      case _Seccion.cuotas:
        _elegirTipoPago();
        break;
      case _Seccion.incidentes:
        _reportarIncidente();
        break;
      case _Seccion.conductores:
        break;
    }
  }

  Future<void> _reportarIncidente() async {
    final parada = _parada;
    final usuarioId = widget.usuario?.id;
    if (parada == null || usuarioId == null) return;
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FormularioIncidenteSheet(
        organizacionId: parada.organizacionId,
        paradaId: parada.id,
        reportadoPor: usuarioId,
        conductoresFuture: _conductoresFuture!,
        service: _detalleService,
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
              subtitle: const Text('Le aparece como pendiente a todos los socios de la parada'),
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
    final parada = _parada;
    final usuarioId = widget.usuario?.id;
    if (parada == null || usuarioId == null) return;
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FormularioLotePagoSheet(
        organizacionId: parada.organizacionId,
        creadoPor: usuarioId,
        service: _lotePagoService,
        esPresidenteAsociacion: false,
        paradaIdFija: parada.id,
        paradaNombreFija: parada.nombre,
        conductoresFuture: _conductoresFuture,
      ),
    );
    if (creado == true) _refrescar();
  }

  Future<void> _registrarCuota() async {
    final parada = _parada;
    final usuarioId = widget.usuario?.id;
    if (parada == null || usuarioId == null) return;
    final creada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FormularioCuotaSheet(
        organizacionId: parada.organizacionId,
        paradaId: parada.id,
        registradoPor: usuarioId,
        conductoresFuture: _conductoresFuture!,
        service: _detalleService,
      ),
    );
    if (creada == true) _refrescar();
  }

  Future<void> _cambiarEstadoCuota(CuotaItem cuota) async {
    final cambiado = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => CambiarEstadoCuotaSheet(cuota: cuota, service: _detalleService),
    );
    if (cambiado == true) _refrescar();
  }

  void _abrirBalancePagos() {
    final parada = _parada;
    if (parada == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BalancePagosScreen(
          paradaId: parada.id,
          paradaNombre: parada.nombre,
          service: _detalleService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accion = _parada == null ? null : _tituloAccion(_seccion);
    return Scaffold(
      appBar: AppBar(
        title: Text(_organizacionNombre ?? 'TapePy',
            overflow: TextOverflow.ellipsis, maxLines: 1),
        actions: [
          if (_parada != null && widget.usuario != null)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimir listado',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ImprimirListadoScreen(
                    paradaId: _parada!.id,
                    paradaNombre: _parada!.nombre,
                    usuario: widget.usuario!,
                  ),
                ),
              ),
            ),
        ],
      ),
      drawer: MenuLateral(
        usuario: widget.usuario,
        noLeidosFuture: _noLeidosFuture,
        onCerrarSesion: _cerrarSesion,
        itemsExtra: _parada == null
            ? []
            : [
                ItemMenuLateral(
                  icono: Icons.how_to_reg_outlined,
                  titulo: 'Solicitudes pendientes',
                  contador: _totalSolicitudesPendientes > 0 ? _totalSolicitudesPendientes : null,
                  onTap: () {
                    final id = widget.usuario?.id;
                    Navigator.of(context).pop();
                    if (id == null) return;
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                          builder: (_) => SolicitudesPendientesScreen(
                            paradaId: _parada!.id,
                            paradaNombre: _parada!.nombre,
                            usuarioId: id,
                          ),
                        ))
                        .then((_) {
                      _cargarSolicitudesPendientes(_parada!.id);
                      _cargarSolicitudesFirma();
                    });
                  },
                ),
                ItemMenuLateral(
                  icono: Icons.credit_card_outlined,
                  titulo: 'Vencimientos de carnet',
                  onTap: () {
                    final usuario = widget.usuario;
                    Navigator.of(context).pop();
                    if (usuario == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VencimientosCarnetScreen(
                          usuario: usuario,
                          paradaId: _parada!.id,
                          paradaNombre: _parada!.nombre,
                        ),
                      ),
                    );
                  },
                ),
                ItemMenuLateral(
                  icono: Icons.draw_outlined,
                  titulo: 'Mi firma digital',
                  onTap: () {
                    final usuario = widget.usuario;
                    Navigator.of(context).pop();
                    if (usuario == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => MiFirmaScreen(usuario: usuario)),
                    );
                  },
                ),
                ItemMenuLateral(
                  icono: Icons.badge_outlined,
                  titulo: 'Mi perfil de socio',
                  onTap: () {
                    final usuario = widget.usuario;
                    Navigator.of(context).pop();
                    if (usuario == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MiPerfilSocioScreen(
                          usuario: usuario,
                          paradaIdSugerida: _parada!.id,
                          paradaNombreSugerida: _parada!.nombre,
                        ),
                      ),
                    );
                  },
                ),
              ],
      ),
      floatingActionButton: accion == null
          ? null
          : FloatingActionButton.extended(
              key: ValueKey('fab_${_seccion.name}'),
              onPressed: _onAccion,
              backgroundColor: AppTheme.rojoInstitucional,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(accion, style: const TextStyle(color: Colors.white)),
            ),
      body: _cargandoParada
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refrescar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _parada == null
                    ? [
                        _SaludoPresidenteParada(usuario: widget.usuario),
                        const SizedBox(height: 24),
                        const _SinParadaAsignada(),
                      ]
                    : [
                        FutureBuilder<ParadaResumen>(
                          future: _resumenFuture,
                          builder: (context, snapshot) => _EncabezadoMiParada(
                            nombre: _parada!.nombre,
                            ubicacion: _parada!.ubicacion,
                            resumen: snapshot.data,
                            solicitudesPendientes: _totalSolicitudesPendientes,
                            usuario: widget.usuario,
                          ),
                        ),
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
                        const SizedBox(height: 90),
                      ],
              ),
            ),
    );
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
            const _Aviso(
              texto: 'Cada conductor se registra y completa su propio perfil, y prende o '
                  'apaga su propia bandera de "en servicio". Acá solo consultás.',
            ),
            const SizedBox(height: 12),
            _ListaConductores(
                future: _conductoresFuture!, onEliminar: _eliminarConductor, service: _detalleService),
          ],
        );
      case _Seccion.cuotas:
        return Column(
          key: const ValueKey('cuotas'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _abrirBalancePagos,
                icon: const Icon(Icons.bar_chart_outlined),
                label: const Text('Ver balance de pagos'),
              ),
            ),
            const SizedBox(height: 8),
            _ListaCuotas(future: _cuotasFuture!, onTap: _cambiarEstadoCuota),
          ],
        );
      case _Seccion.documentos:
        return Column(
          key: const ValueKey('documentos'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Aviso(
              texto: 'Los documentos de cada conductor los sube él mismo. Los de la '
                  'parada (ej. habilitación municipal) los subís vos con el botón de abajo.',
            ),
            const SizedBox(height: 12),
            _ListaDocumentos(future: _documentosFuture!, service: _detalleService),
          ],
        );
      case _Seccion.incidentes:
        return _ListaIncidentes(key: const ValueKey('incidentes'), future: _incidentesFuture!);
      case _Seccion.convenios:
        return _ListaConvenios(
          key: const ValueKey('convenios'),
          future: _conveniosFuture!,
          onEliminar: _eliminarConvenio,
        );
    }
  }
}

/// ---------------------------------------------------------------------
/// Encabezado / estado sin asignar
/// ---------------------------------------------------------------------

class _SaludoPresidenteParada extends StatelessWidget {
  final Usuario? usuario;
  const _SaludoPresidenteParada({required this.usuario});

  String get _saludo {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final nombre = usuario?.nombre ?? 'Presidente';
    final inicial = nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : 'P';
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
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                backgroundImage:
                    usuario?.fotoPerfilUrl != null ? NetworkImage(usuario!.fotoPerfilUrl!) : null,
                child: usuario?.fotoPerfilUrl == null
                    ? Text(inicial,
                        style: const TextStyle(
                            color: AppTheme.rojoInstitucional, fontWeight: FontWeight.bold, fontSize: 20))
                    : null,
              ),
              const SizedBox(width: 14),
              // Expanded + Column propio (no comparte fila con el
              // switch de "en servicio"): en un celular real, todo
              // junto en un Row deja muy poco ancho para el nombre.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_saludo, $nombre',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    const Text('Presidente de Parada', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          if (usuario != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: EnServicioSwitch(usuarioId: usuario!.id, valorInicial: usuario!.enServicio),
            ),
          ],
        ],
      ),
    );
  }
}

class _SinParadaAsignada extends StatelessWidget {
  const _SinParadaAsignada();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.signpost_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text(
              'Todavía no fuiste asignado como presidente de ninguna parada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Contactá al presidente de tu asociación para que te asigne.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _EncabezadoMiParada extends StatelessWidget {
  final String nombre;
  final String? ubicacion;
  final ParadaResumen? resumen;
  final int solicitudesPendientes;
  final Usuario? usuario;
  const _EncabezadoMiParada({
    required this.nombre,
    this.ubicacion,
    this.resumen,
    this.solicitudesPendientes = 0,
    this.usuario,
  });

  static String get _saludo {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final estado = resumen?.estado;
    final nombreUsuario = usuario?.nombre;
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
          // Saludo a la persona logueada — antes esta pantalla solo
          // mostraba el nombre de la parada y nunca saludaba, a
          // diferencia del panel de asociación y el de conductor.
          if (nombreUsuario != null && nombreUsuario.trim().isNotEmpty) ...[
            Text('$_saludo, $nombreUsuario',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            const Text('Presidente de Parada', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              const IconBadge(icono: Icons.location_pin, color: Colors.white24, diametro: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    if (ubicacion != null && ubicacion!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(ubicacion!,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                      ),
                  ],
                ),
              ),
              if (estado != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(estado.etiqueta,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
            ],
          ),
          if (usuario != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: EnServicioSwitch(usuarioId: usuario!.id, valorInicial: usuario!.enServicio),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat(valor: '${resumen?.conductoresCount ?? '–'}', etiqueta: 'Conductores'),
              _MiniStat(valor: '${resumen?.cuotasAtrasadasCount ?? '–'}', etiqueta: 'Atrasados'),
              _MiniStat(
                valor: '$solicitudesPendientes',
                etiqueta: 'Por revisar',
                destacar: solicitudesPendientes > 0,
              ),
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
  final bool destacar;
  const _MiniStat({required this.valor, required this.etiqueta, this.destacar = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(valor,
              style: TextStyle(
                color: destacar ? AppTheme.estadoAtencion : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              )),
          Text(etiqueta,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;
  const _Aviso({required this.texto});

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
          Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

/// Barra horizontal de íconos — mismo lenguaje visual que
/// parada_detalle_screen.dart, con una sección más (Convenios).
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
      (_Seccion.convenios, Icons.handshake_outlined, 'Convenios'),
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
              margin: const EdgeInsets.symmetric(horizontal: 2),
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
                    diametro: 40,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    etiqueta,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
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
/// Secciones (conductores/cuotas/documentos/incidentes: mismas tarjetas
/// que ya usa el presidente de asociación en parada_detalle_screen.dart)
/// ---------------------------------------------------------------------

class _ListaConductores extends StatelessWidget {
  final Future<List<ConductorItem>> future;
  final void Function(ConductorItem) onEliminar;
  final ParadaDetalleService service;
  const _ListaConductores({
    super.key,
    required this.future,
    required this.onEliminar,
    required this.service,
  });

  static String _turnoLabel(String turno) {
    const labels = {'manana': 'Mañana', 'tarde': 'Tarde', 'noche': 'Noche', 'completo': 'Completo'};
    return labels[turno] ?? turno;
  }

  void _abrirVehiculos(BuildContext context, ConductorItem item) {
    mostrarVehiculosConductorSheet(
      context,
      conductorId: item.id,
      nombreConductor: item.nombre,
      service: service,
    );
  }

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
          onTap: () => _abrirVehiculos(context, item),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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
                        'Resolución Nº (socio) ${item.resolucionNumero}',
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
}

class _ListaCuotas extends StatelessWidget {
  final Future<List<CuotaItem>> future;
  final void Function(CuotaItem) onTap;
  const _ListaCuotas({super.key, required this.future, required this.onTap});

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
    const labels = {'pagado': 'Pagado', 'atrasado': 'Atrasado', 'pendiente': 'Pendiente', 'exonerado': 'Exonerado'};
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
            onTap: () => onTap(item),
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
                    child: Text(_labelEstado(item.estado),
                        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
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

class _ListaDocumentos extends StatelessWidget {
  final Future<List<DocumentoItem>> future;
  final ParadaDetalleService service;
  const _ListaDocumentos({super.key, required this.future, required this.service});

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
        final tieneDescripcion = item.descripcion != null && item.descripcion!.isNotEmpty;
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
                      Text(
                          tieneDescripcion
                              ? '${item.entidad} · ${item.descripcion}'
                              : '${item.entidad} · ${_labelTipo(item.tipo)}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      if (tieneDescripcion)
                        Text(_labelTipo(item.tipo),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                  child: Text(_labelEstado(item.estado),
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
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

class _ListaIncidentes extends StatelessWidget {
  final Future<List<IncidenteItem>> future;
  const _ListaIncidentes({super.key, required this.future});

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
    const labels = {'accidente': 'Accidente', 'mecanico': 'Falla mecánica', 'conflicto': 'Conflicto', 'otro': 'Otro'};
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
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
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
                  child: Text(_labelEstado(item.estado),
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ListaConvenios extends StatelessWidget {
  final Future<List<ConvenioItem>> future;
  final void Function(ConvenioItem) onEliminar;
  const _ListaConvenios({super.key, required this.future, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    return _ListaAsync<ConvenioItem>(
      future: future,
      vacioIcono: Icons.handshake_outlined,
      vacioTexto: 'Todavía no hay convenios cargados para esta parada',
      itemBuilder: (item) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(
                icono: Icons.handshake_outlined,
                color: item.activo ? AppTheme.rojoInstitucional : Colors.grey.shade400,
                diametro: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.empresaNombre,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (item.descripcion != null && item.descripcion!.isNotEmpty)
                      Text(
                        item.descripcion!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                onPressed: () => onEliminar(item),
                tooltip: 'Eliminar convenio',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget genérico: carga, vacío o lista.
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

/// ---------------------------------------------------------------------
/// Formularios (subir documento de parada / nuevo convenio)
/// ---------------------------------------------------------------------

class _FormularioDocumentoParada extends StatefulWidget {
  final String organizacionId;
  final String paradaId;
  final String usuarioId;
  final ParadaPresidenteService service;
  const _FormularioDocumentoParada({
    required this.organizacionId,
    required this.paradaId,
    required this.usuarioId,
    required this.service,
  });

  @override
  State<_FormularioDocumentoParada> createState() => _FormularioDocumentoParadaState();
}

class _FormularioDocumentoParadaState extends State<_FormularioDocumentoParada> {
  String _tipo = 'habilitacion_municipal';
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
    final archivo = await ImagePicker().pickImage(source: origen, maxWidth: 1600, imageQuality: 85);
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
      await widget.service.subirDocumentoParada(
        organizacionId: widget.organizacionId,
        paradaId: widget.paradaId,
        usuarioId: widget.usuarioId,
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
          Text('Documento de la parada', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _tipo,
            decoration:
                const InputDecoration(labelText: 'Tipo de documento', border: OutlineInputBorder()),
            items: _tiposDocumentoParada.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (value) => setState(() => _tipo = value ?? _tipo),
          ),
          if (_esOtro) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _descripcionController,
              decoration: const InputDecoration(
                labelText: 'Qué documento es',
                hintText: 'Ej: Nota del municipio, plano de la parada',
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
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Subir'),
          ),
        ],
      ),
    );
  }
}

class _FormularioConvenio extends StatefulWidget {
  final String organizacionId;
  final String paradaId;
  final String usuarioId;
  final ParadaPresidenteService service;
  const _FormularioConvenio({
    required this.organizacionId,
    required this.paradaId,
    required this.usuarioId,
    required this.service,
  });

  @override
  State<_FormularioConvenio> createState() => _FormularioConvenioState();
}

class _FormularioConvenioState extends State<_FormularioConvenio> {
  final _formKey = GlobalKey<FormState>();
  final _empresaController = TextEditingController();
  final _descripcionController = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _empresaController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.crearConvenio(
        organizacionId: widget.organizacionId,
        paradaId: widget.paradaId,
        creadoPor: widget.usuarioId,
        empresaNombre: _empresaController.text.trim(),
        descripcion: _descripcionController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nuevo convenio', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Empresa que tiene un acuerdo de publicidad con esta parada.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _empresaController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Empresa', border: OutlineInputBorder()),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Ingresá el nombre de la empresa' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descripcionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Detalle (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
              child: _guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar convenio'),
            ),
          ],
        ),
      ),
    );
  }
}

