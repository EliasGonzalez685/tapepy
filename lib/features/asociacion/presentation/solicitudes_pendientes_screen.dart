import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../constancia/data/constancia_service.dart';
import '../../firma/data/firma_service.dart';
import '../data/parada_detalle_service.dart';

/// Bandeja única de solicitudes que le llegan al presidente: altas de
/// conductores sin aprobar todavía (pestaña "Registros") y pedidos de
/// otro presidente para usar su firma en un listado (pestaña "Firmas").
/// Sirve tanto para el presidente de una parada (pasa [paradaId]) como
/// para el presidente de asociación, que ve los registros de todas las
/// paradas (no pasa ninguno de los dos parámetros de parada).
class SolicitudesPendientesScreen extends StatefulWidget {
  final String? paradaId;
  final String? paradaNombre;
  final String usuarioId;
  // Solo lo usa el dueño de plataforma, para acotar la vista "todas las
  // paradas" a una única organización (por RLS ve todas juntas).
  final String? organizacionId;
  const SolicitudesPendientesScreen({
    super.key,
    required this.usuarioId,
    this.paradaId,
    this.paradaNombre,
    this.organizacionId,
  });

  bool get _todasLasParadas => paradaId == null;

  @override
  State<SolicitudesPendientesScreen> createState() => _SolicitudesPendientesScreenState();
}

class _SolicitudesPendientesScreenState extends State<SolicitudesPendientesScreen>
    with SingleTickerProviderStateMixin {
  final _service = ParadaDetalleService();
  final _firmaService = FirmaService();
  final _constanciaService = ConstanciaService();
  late final TabController _tabController;

  late Future<List<SolicitudPendienteItem>> _futureRegistros;
  final Set<String> _procesandoRegistro = {};

  late Future<List<SolicitudFirmaItem>> _futureFirmas;
  final Set<String> _procesandoFirma = {};

  // Las constancias solo las resuelve el presidente de asociación (o el
  // dueño de plataforma supervisando), nunca el presidente de una
  // parada puntual — por eso la pestaña solo existe cuando esta
  // pantalla se abrió en modo "todas las paradas".
  Future<List<SolicitudConstanciaItem>>? _futureConstancias;
  final Set<String> _procesandoConstancia = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget._todasLasParadas ? 3 : 2, vsync: this);
    _cargarRegistros();
    _cargarFirmas();
    if (widget._todasLasParadas) _cargarConstancias();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _cargarRegistros() {
    _futureRegistros = widget._todasLasParadas
        ? _service.cargarSolicitudesPendientesOrganizacion(organizacionId: widget.organizacionId)
        : _service.cargarSolicitudesPendientes(widget.paradaId!);
  }

  void _cargarFirmas() {
    _futureFirmas = _firmaService.cargarSolicitudesPendientes(widget.usuarioId);
  }

  void _cargarConstancias() {
    final organizacionId = widget.organizacionId;
    if (organizacionId == null) return;
    _futureConstancias = _constanciaService.cargarSolicitudesPendientes(organizacionId: organizacionId);
  }

  Future<void> _refrescarRegistros() async {
    setState(_cargarRegistros);
    await _futureRegistros;
  }

  Future<void> _refrescarFirmas() async {
    setState(_cargarFirmas);
    await _futureFirmas;
  }

  Future<void> _refrescarConstancias() async {
    if (!widget._todasLasParadas) return;
    setState(_cargarConstancias);
    await _futureConstancias;
  }

  Future<void> _aceptarRegistro(SolicitudPendienteItem item) async {
    setState(() => _procesandoRegistro.add(item.usuarioId));
    try {
      await _service.aprobarConductor(item.usuarioId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.nombre} ya puede iniciar sesión')),
      );
      await _refrescarRegistros();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo aprobar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _procesandoRegistro.remove(item.usuarioId));
    }
  }

  Future<void> _rechazarRegistro(SolicitudPendienteItem item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Text(
          '¿Rechazar el registro de "${item.nombre}"? Se elimina la cuenta por completo, '
          'va a tener que registrarse de nuevo si quiere volver a intentarlo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Rechazar', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesandoRegistro.add(item.usuarioId));
    try {
      await _service.eliminarConductor(item.usuarioId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Se eliminó la solicitud de ${item.nombre}')));
      await _refrescarRegistros();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo rechazar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _procesandoRegistro.remove(item.usuarioId));
    }
  }

  Future<void> _resolverFirma(SolicitudFirmaItem item, bool aprobar) async {
    setState(() => _procesandoFirma.add(item.id));
    try {
      await _firmaService.resolverSolicitud(solicitudId: item.id, aprobar: aprobar);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(aprobar ? 'Firma autorizada para ${item.solicitanteNombre}' : 'Solicitud rechazada'),
        ),
      );
      await _refrescarFirmas();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo procesar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _procesandoFirma.remove(item.id));
    }
  }

  Future<void> _resolverConstancia(
    SolicitudConstanciaItem item, {
    required bool aprobar,
    String? tipoSocio,
  }) async {
    setState(() => _procesandoConstancia.add(item.id));
    try {
      await _constanciaService.resolverSolicitud(
        solicitudId: item.id,
        aprobar: aprobar,
        tipoSocio: tipoSocio,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(aprobar ? 'Constancia aprobada para ${item.solicitanteNombre}' : 'Solicitud rechazada')),
      );
      await _refrescarConstancias();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo procesar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _procesandoConstancia.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOLICITUDES PENDIENTES'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.how_to_reg_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('Registros'),
                  _Contador(future: _futureRegistros),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.draw_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('Firmas'),
                  _Contador(future: _futureFirmas),
                ],
              ),
            ),
            if (widget._todasLasParadas)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 6),
                    const Text('Constancias'),
                    if (_futureConstancias != null) _Contador(future: _futureConstancias!),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RegistrosTab(
            future: _futureRegistros,
            procesando: _procesandoRegistro,
            onRefrescar: _refrescarRegistros,
            onAceptar: _aceptarRegistro,
            onRechazar: _rechazarRegistro,
          ),
          _FirmasTab(
            future: _futureFirmas,
            procesando: _procesandoFirma,
            onRefrescar: _refrescarFirmas,
            onResolver: _resolverFirma,
          ),
          if (widget._todasLasParadas)
            _ConstanciasTab(
              future: _futureConstancias!,
              procesando: _procesandoConstancia,
              onRefrescar: _refrescarConstancias,
              onResolver: _resolverConstancia,
            ),
        ],
      ),
    );
  }
}

/// Numerito chico al lado del texto de la pestaña, solo si ya cargó y
/// hay al menos una solicitud.
class _Contador extends StatelessWidget {
  final Future<List<dynamic>> future;
  const _Contador({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: future,
      builder: (context, snapshot) {
        final cantidad = snapshot.data?.length ?? 0;
        if (cantidad == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: CircleAvatar(
            radius: 9,
            backgroundColor: AppTheme.rojoInstitucional,
            child: Text('$cantidad', style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        );
      },
    );
  }
}

class _RegistrosTab extends StatelessWidget {
  final Future<List<SolicitudPendienteItem>> future;
  final Set<String> procesando;
  final Future<void> Function() onRefrescar;
  final void Function(SolicitudPendienteItem) onAceptar;
  final void Function(SolicitudPendienteItem) onRechazar;

  const _RegistrosTab({
    required this.future,
    required this.procesando,
    required this.onRefrescar,
    required this.onAceptar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefrescar,
      child: FutureBuilder<List<SolicitudPendienteItem>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text('No se pudo cargar: ${snapshot.error}')),
              ],
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Icon(Icons.how_to_reg_outlined,
                            size: 40, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                          'No hay registros pendientes por el momento',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final procesandoItem = procesando.contains(item.usuarioId);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const IconBadge(
                              icono: Icons.person_outline, color: AppTheme.estadoAtencion, diametro: 44),
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
                                    if (item.cedula != null) 'CI ${item.cedula}',
                                    if (item.telefono != null) item.telefono!,
                                    if (item.paradaNombre != null) item.paradaNombre!,
                                  ].join(' · '),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                                Text(
                                  'Se registró el ${formatoFecha.format(item.creadoEn)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (procesandoItem)
                        const Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => onRechazar(item),
                              style:
                                  TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                              child: const Text('Rechazar'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => onAceptar(item),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                              child: const Text('Aceptar'),
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

class _FirmasTab extends StatelessWidget {
  final Future<List<SolicitudFirmaItem>> future;
  final Set<String> procesando;
  final Future<void> Function() onRefrescar;
  final void Function(SolicitudFirmaItem, bool aprobar) onResolver;

  const _FirmasTab({
    required this.future,
    required this.procesando,
    required this.onRefrescar,
    required this.onResolver,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefrescar,
      child: FutureBuilder<List<SolicitudFirmaItem>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text('No se pudo cargar: ${snapshot.error}')),
              ],
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Icon(Icons.draw_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                          'No hay solicitudes de firma pendientes',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final procesandoItem = procesando.contains(item.id);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const IconBadge(
                              icono: Icons.draw_outlined, color: AppTheme.rojoInstitucional, diametro: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.solicitanteNombre,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                Text(item.solicitanteRolLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                if (item.paradaNombre != null)
                                  Text('Para el listado de ${item.paradaNombre}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (procesandoItem)
                        const Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => onResolver(item, false),
                              style:
                                  TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                              child: const Text('Rechazar'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => onResolver(item, true),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                              child: const Text('Autorizar'),
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

class _ConstanciasTab extends StatelessWidget {
  final Future<List<SolicitudConstanciaItem>> future;
  final Set<String> procesando;
  final Future<void> Function() onRefrescar;
  final Future<void> Function(SolicitudConstanciaItem, {required bool aprobar, String? tipoSocio}) onResolver;

  const _ConstanciasTab({
    required this.future,
    required this.procesando,
    required this.onRefrescar,
    required this.onResolver,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefrescar,
      child: FutureBuilder<List<SolicitudConstanciaItem>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text('No se pudo cargar: ${snapshot.error}')),
              ],
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Icon(Icons.description_outlined,
                            size: 40, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                          'No hay solicitudes de constancia pendientes',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          final formatoFecha = DateFormat('dd/MM/yyyy');
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final procesandoItem = procesando.contains(item.id);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const IconBadge(
                              icono: Icons.description_outlined, color: AppTheme.rojoInstitucional, diametro: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.solicitanteNombre,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (item.solicitanteCedula != null) 'CI ${item.solicitanteCedula}',
                                    item.paradaNombre,
                                  ].join(' · '),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                                Text(
                                  'Pedida el ${formatoFecha.format(item.creadoEn)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (procesandoItem)
                        const Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => onResolver(item, aprobar: false),
                              style:
                                  TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                              child: const Text('Rechazar'),
                            ),
                            OutlinedButton(
                              onPressed: () => onResolver(item, aprobar: true, tipoSocio: 'chofer'),
                              child: const Text('Aprobar: chofer'),
                            ),
                            FilledButton(
                              onPressed: () => onResolver(item, aprobar: true, tipoSocio: 'socio propietario'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                              child: const Text('Aprobar: propietario'),
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
