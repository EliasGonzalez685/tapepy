import 'package:flutter/material.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/en_servicio_switch.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../../shared/widgets/menu_lateral.dart';
import '../../auth/data/auth_service.dart';
import '../../conductor/presentation/mi_perfil_socio_screen.dart';
import '../../constancia/data/constancia_service.dart';
import '../../firma/data/firma_service.dart';
import '../../firma/presentation/mi_firma_screen.dart';
import '../../mensajeria/data/mensajeria_service.dart';
import '../data/asociacion_dashboard_service.dart';
import '../data/parada_detalle_service.dart';
import '../data/parada_resumen.dart';
import 'convenios_organizacion_screen.dart';
import 'imprimir_listado_screen.dart';
import 'miembros_activos_screen.dart';
import 'parada_detalle_screen.dart';
import 'paradas_screen.dart';
import 'solicitudes_pendientes_screen.dart';
import 'vencimientos_carnet_screen.dart';

/// Home del rol presidente de asociación: vista global de paradas,
/// cuotas, incidentes y mensajería.
class AsociacionHomeScreen extends StatefulWidget {
  final Usuario? usuario;
  // Ítems extra para el drawer, además de los propios de este panel.
  // Los usa el dueño de plataforma para sumar "Presidente de
  // asociación" (control que no tiene el propio presidente) al reusar
  // esta misma pantalla — ver DuenoPlataformaHomeScreen.
  final List<ItemMenuLateral> itemsExtraAdicionales;
  const AsociacionHomeScreen({
    super.key,
    this.usuario,
    this.itemsExtraAdicionales = const [],
  });

  @override
  State<AsociacionHomeScreen> createState() => _AsociacionHomeScreenState();
}

class _AsociacionHomeScreenState extends State<AsociacionHomeScreen> {
  final _service = AsociacionDashboardService();
  final _mensajeriaService = MensajeriaService();
  final _paradaDetalleService = ParadaDetalleService();
  final _firmaService = FirmaService();
  final _constanciaService = ConstanciaService();
  final _organizacionService = OrganizacionService();
  late Future<AsociacionDashboardTotales> _future;
  late Future<int> _noLeidosFuture;
  int? _solicitudesPendientesCount;
  int? _solicitudesFirmaCount;
  int? _solicitudesConstanciaCount;
  int? _noLeidosCount;
  String? _organizacionNombre;

  int get _totalSolicitudesPendientes =>
      (_solicitudesPendientesCount ?? 0) + (_solicitudesFirmaCount ?? 0) + (_solicitudesConstanciaCount ?? 0);

  // Todo lo que amerita que el presidente lo vea en primera plana:
  // solicitudes de aprobación/firma pendientes + mensajes sin leer.
  int get _totalAvisos => _totalSolicitudesPendientes + (_noLeidosCount ?? 0);

  @override
  void initState() {
    super.initState();
    _future = _service.cargarResumen(organizacionId: widget.usuario?.organizacionId);
    _noLeidosFuture = _cargarNoLeidos();
    _noLeidosFuture.then((n) {
      if (mounted) setState(() => _noLeidosCount = n);
    });
    _cargarSolicitudesPendientes();
    _cargarSolicitudesFirma();
    _cargarSolicitudesConstancia();
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

  Future<int> _cargarNoLeidos() {
    final id = widget.usuario?.id;
    if (id == null) return Future.value(0);
    return _mensajeriaService.contarNoLeidos(id);
  }

  Future<void> _cargarSolicitudesPendientes() async {
    try {
      final lista = await _paradaDetalleService.cargarSolicitudesPendientesOrganizacion(
        organizacionId: widget.usuario?.organizacionId,
      );
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

  Future<void> _cargarSolicitudesConstancia() async {
    final organizacionId = widget.usuario?.organizacionId;
    if (organizacionId == null) return;
    try {
      final lista = await _constanciaService.cargarSolicitudesPendientes(organizacionId: organizacionId);
      if (!mounted) return;
      setState(() => _solicitudesConstanciaCount = lista.length);
    } catch (_) {
      // Silencioso: el badge es solo un aviso, no bloquea nada si falla.
    }
  }

  Future<void> _refrescar() async {
    setState(() {
      _future = _service.cargarResumen(organizacionId: widget.usuario?.organizacionId);
      _noLeidosFuture = _cargarNoLeidos();
    });
    _noLeidosFuture.then((n) {
      if (mounted) setState(() => _noLeidosCount = n);
    });
    _cargarSolicitudesPendientes();
    _cargarSolicitudesFirma();
    _cargarSolicitudesConstancia();
    await _future;
  }

  void _abrirSolicitudes() {
    final id = widget.usuario?.id;
    if (id == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => SolicitudesPendientesScreen(
                  usuarioId: id,
                  organizacionId: widget.usuario?.organizacionId,
                )))
        .then((_) {
      _cargarSolicitudesPendientes();
      _cargarSolicitudesFirma();
      _cargarSolicitudesConstancia();
    });
  }

  void _abrirMiembrosActivos() {
    final organizacionId = widget.usuario?.organizacionId;
    if (organizacionId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiembrosActivosScreen(organizacionId: organizacionId),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRouter.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_organizacionNombre ?? 'TapePy', overflow: TextOverflow.ellipsis, maxLines: 1)),
      drawer: MenuLateral(
        usuario: widget.usuario,
        noLeidosFuture: _noLeidosFuture,
        onCerrarSesion: _cerrarSesion,
        itemsExtra: [
          ItemMenuLateral(
            icono: Icons.signpost_outlined,
            titulo: 'Paradas',
            onTap: () {
              final organizacionId = widget.usuario?.organizacionId;
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              navigator.pop();
              if (organizacionId == null) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('No se pudo determinar tu organización. Reingresá y probá de nuevo.'),
                  ),
                );
                return;
              }
              navigator
                  .push(
                    MaterialPageRoute(
                      builder: (_) => ParadasScreen(organizacionId: organizacionId),
                    ),
                  )
                  .then((_) => _refrescar());
            },
          ),
          ItemMenuLateral(
            icono: Icons.how_to_reg_outlined,
            titulo: 'Solicitudes pendientes',
            contador: _totalSolicitudesPendientes > 0 ? _totalSolicitudesPendientes : null,
            onTap: () {
              Navigator.of(context).pop();
              _abrirSolicitudes();
            },
          ),
          ItemMenuLateral(
            icono: Icons.flag_outlined,
            titulo: 'Miembros activos',
            onTap: () {
              final organizacionId = widget.usuario?.organizacionId;
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              navigator.pop();
              if (organizacionId == null) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('No se pudo determinar tu organización. Reingresá y probá de nuevo.'),
                  ),
                );
                return;
              }
              _abrirMiembrosActivos();
            },
          ),
          ItemMenuLateral(
            icono: Icons.credit_card_outlined,
            titulo: 'Vencimientos de carnet',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VencimientosCarnetScreen(usuario: widget.usuario),
                ),
              );
            },
          ),
          ItemMenuLateral(
            icono: Icons.handshake_outlined,
            titulo: 'Convenios',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ConveniosOrganizacionScreen(
                    organizacionId: widget.usuario?.organizacionId,
                  ),
                ),
              );
            },
          ),
          ItemMenuLateral(
            icono: Icons.print_outlined,
            titulo: 'Imprimir listado',
            onTap: () {
              final usuario = widget.usuario;
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              navigator.pop();
              if (usuario == null) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('No se pudo determinar tu usuario. Reingresá y probá de nuevo.'),
                  ),
                );
                return;
              }
              navigator.push(
                MaterialPageRoute(builder: (_) => ImprimirListadoScreen(usuario: usuario)),
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
                MaterialPageRoute(builder: (_) => MiPerfilSocioScreen(usuario: usuario)),
              );
            },
          ),
          ...widget.itemsExtraAdicionales,
        ],
      ),
      body: FutureBuilder<AsociacionDashboardTotales>(
        future: _future,
        builder: (context, snapshot) {
          final cargando = snapshot.connectionState == ConnectionState.waiting;

          if (snapshot.hasError && !cargando) {
            return _ErrorState(onRetry: _refrescar);
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: cargando
                ? const _DashboardSkeleton(key: ValueKey('skeleton'))
                : RefreshIndicator(
                    key: const ValueKey('contenido'),
                    onRefresh: _refrescar,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _GreetingHeader(usuario: widget.usuario),
                        const SizedBox(height: 20),
                        _StatsGrid(
                          datos: snapshot.data!,
                          avisos: _totalAvisos,
                          onTapAvisos: _abrirSolicitudes,
                        ),
                        const SizedBox(height: 16),
                        _EnServicioBanner(
                          activos: snapshot.data!.conductoresActivos,
                          total: snapshot.data!.miembros,
                          onTap: _abrirMiembrosActivos,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Estado de paradas',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        if (snapshot.data!.paradas.isEmpty)
                          const _SinParadas()
                        else
                          ...snapshot.data!.paradas
                              .map((p) => _ParadaCard(parada: p, usuario: widget.usuario)),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final Usuario? usuario;
  const _GreetingHeader({required this.usuario});

  String get _saludo {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  // Normalmente es "Presidente de Asociación", pero cuando el dueño de
  // plataforma reusa esta misma pantalla para supervisar una
  // organización, tiene que verse su rol real, no el ajeno.
  String get _rolLabel => usuario?.rol.label ?? 'Presidente de Asociación';

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
          colors: [
            AppTheme.rojoInstitucional,
            AppTheme.rojoInstitucional.withValues(alpha: 0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo real de Traude (la organización). El saludo de al
              // lado usa el nombre de la persona logueada — son cosas
              // distintas.
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                backgroundImage: const AssetImage('assets/images/traude_logo.png'),
                onBackgroundImageError: (_, __) {},
                child: usuario == null
                    ? Text(
                        inicial,
                        style: const TextStyle(
                          color: AppTheme.rojoInstitucional,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              // Expanded + Column propio (no comparte fila con el
              // switch de "en servicio"): en un celular real, un Row
              // con avatar + nombre + switch todos juntos deja muy
              // poco ancho para el nombre y lo trunca de entrada.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_saludo, $nombre',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _rolLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // El dueño de plataforma no hace trabajo de campo de ninguna
          // asociación puntual — la bandera "en servicio" no le
          // corresponde (mismo criterio que carnet/QR en MenuLateral).
          // Va en su propia fila, debajo, para no competir por ancho
          // con el nombre.
          if (usuario != null && usuario!.rol != UserRole.duenoPlataforma) ...[
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

// Dashboard sin "Cuotas atrasadas" ni "Docs por vencer": esos números son
// detalle de cada parada/conductor y el presidente ya los ve al entrar
// ahí (subtítulo de cada _ParadaCard, o dentro de ParadaDetalleScreen).
// Acá arriba solo va lo que amerita primera plana: cuántos miembros hay,
// y si hay algo pendiente de revisar (solicitudes o mensajes).
class _StatsGrid extends StatelessWidget {
  final AsociacionDashboardTotales datos;
  final int avisos;
  final VoidCallback onTapAvisos;
  const _StatsGrid({required this.datos, required this.avisos, required this.onTapAvisos});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          icono: Icons.groups_outlined,
          valor: '${datos.miembros}',
          etiqueta: 'Miembros',
        ),
        _StatCard(
          icono: Icons.notifications_active_outlined,
          valor: '$avisos',
          etiqueta: 'Por revisar',
          destacar: avisos > 0,
          colorDestacado: AppTheme.estadoAtencion,
          onTap: avisos > 0 ? onTapAvisos : null,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String etiqueta;
  final bool destacar;
  final Color? colorDestacado;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icono,
    required this.valor,
    required this.etiqueta,
    this.destacar = false,
    this.colorDestacado,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = destacar
        ? (colorDestacado ?? AppTheme.estadoUrgente)
        : Theme.of(context).colorScheme.primary;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(icono: icono, color: color, diametro: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      valor,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: destacar
                                ? color
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      etiqueta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulso en vivo, org-wide: cuántos conductores están en servicio ahora
/// mismo, sumado entre todas las paradas. El detalle por parada ya vive
/// en el subtítulo de cada _ParadaCard; esto es solo el vistazo rápido
/// de arriba — tocarlo lleva al detalle completo (Miembros activos).
class _EnServicioBanner extends StatelessWidget {
  final int activos;
  final int total;
  final VoidCallback onTap;
  const _EnServicioBanner({required this.activos, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.estadoOk.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.flag, color: AppTheme.estadoOk, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$activos de $total conductores en servicio ahora',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.estadoOk, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ParadaCard extends StatelessWidget {
  final ParadaResumen parada;
  final Usuario? usuario;
  const _ParadaCard({required this.parada, this.usuario});

  @override
  Widget build(BuildContext context) {
    final estado = parada.estado;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ParadaDetalleScreen(parada: parada, usuario: usuario)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Silueta interactiva: círculo de color de estado con ícono de parada.
              IconBadge(
                icono: Icons.location_pin,
                color: estado.color,
                diametro: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parada.nombre,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parada.subtitulo,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: estado.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  estado.etiqueta,
                  style: TextStyle(
                    color: estado.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  color: Theme.of(context).colorScheme.outline, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SinParadas extends StatelessWidget {
  const _SinParadas();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.signpost_outlined,
                size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text(
              'Todavía no hay paradas cargadas',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No se pudieron cargar los datos.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

/// Siluetas animadas (shimmer liviano, sin dependencias extra) mientras
/// carga la información real desde Supabase.
class _DashboardSkeleton extends StatefulWidget {
  const _DashboardSkeleton({super.key});

  @override
  State<_DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<_DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.4, end: 1.0)),
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const _SkeletonBox(height: 88),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: List.generate(2, (_) => const _SkeletonBox(height: 90)),
          ),
          const SizedBox(height: 16),
          const _SkeletonBox(height: 48),
          const SizedBox(height: 20),
          const _SkeletonBox(height: 20, width: 140),
          const SizedBox(height: 12),
          ...List.generate(
            3,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: _SkeletonBox(height: 72),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;
  final double? width;
  const _SkeletonBox({required this.height, this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
