import 'package:flutter/material.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/en_servicio_switch.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../../shared/widgets/menu_lateral.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../auth/data/auth_service.dart';
import '../../mensajeria/data/mensajeria_service.dart';
import '../data/conductor_service.dart';
import 'mi_vehiculo_screen.dart';
import 'mis_cuotas_screen.dart';
import 'mis_documentos_screen.dart';

/// Home del rol conductor: su propio perfil de manejo, vehículo,
/// documentos (los sube él, nadie más) y sus cuotas (solo lectura).
class ConductorHomeScreen extends StatefulWidget {
  final Usuario? usuario;
  const ConductorHomeScreen({super.key, this.usuario});

  @override
  State<ConductorHomeScreen> createState() => _ConductorHomeScreenState();
}

class _ConductorHomeScreenState extends State<ConductorHomeScreen> {
  final _service = ConductorService();
  final _mensajeriaService = MensajeriaService();
  final _organizacionService = OrganizacionService();
  late Future<ConductorPerfil?> _future;
  late Future<int> _noLeidosFuture;
  String? _organizacionNombre;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    _cargarOrganizacion();
  }

  void _cargarTodo() {
    final id = widget.usuario?.id;
    _future = id == null ? Future.value(null) : _service.cargarPerfil(id);
    _noLeidosFuture = id == null ? Future.value(0) : _mensajeriaService.contarNoLeidos(id);
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

  Future<void> _refrescar() async {
    setState(_cargarTodo);
    await _future;
  }

  Future<void> _cerrarSesion() async {
    await AuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRouter.login, (route) => false);
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
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<ConductorPerfil?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final perfil = snapshot.data;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SaludoConductor(usuario: widget.usuario, parada: perfil?.paradaNombre),
                const SizedBox(height: 24),
                if (perfil == null)
                  const _SinAsignar()
                else ...[
                  Text('Mi actividad', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _AccesoCard(
                    icono: Icons.directions_car_filled_outlined,
                    color: AppTheme.rojoInstitucional,
                    titulo: 'Mi vehículo',
                    subtitulo: perfil.vehiculo == null || perfil.vehiculo!.estaVacio
                        ? 'Todavía no cargaste los datos'
                        : '${perfil.vehiculo!.marca ?? ''} ${perfil.vehiculo!.modelo ?? ''} · ${perfil.vehiculo!.chapa ?? ''}',
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MiVehiculoScreen(perfil: perfil)));
                      if (mounted) _refrescar();
                    },
                  ),
                  const SizedBox(height: 10),
                  _AccesoCard(
                    icono: Icons.description_outlined,
                    color: AppTheme.estadoAtencion,
                    titulo: 'Mis documentos',
                    subtitulo: 'Cédula, licencia, seguro y más — los subís vos',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MisDocumentosScreen(
                            perfil: perfil, usuarioId: widget.usuario!.id))),
                  ),
                  const SizedBox(height: 10),
                  _AccesoCard(
                    icono: Icons.payments_outlined,
                    color: AppTheme.estadoOk,
                    titulo: 'Mis pagos',
                    subtitulo: 'Estado de tus pagos mensuales',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MisCuotasScreen(usuario: widget.usuario!))),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SaludoConductor extends StatelessWidget {
  final Usuario? usuario;
  final String? parada;
  const _SaludoConductor({required this.usuario, required this.parada});

  String get _saludo {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Buenos días';
    if (hora < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final nombre = usuario?.nombre ?? 'Conductor';
    final inicial = nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : 'C';

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
                    Text(
                      parada != null ? 'Conductor · $parada' : 'Conductor',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                    ),
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

class _AccesoCard extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  const _AccesoCard({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(icono: icono, color: color, diametro: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _SinAsignar extends StatelessWidget {
  const _SinAsignar();

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
              'Todavía no estás asignado a ninguna parada.',
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
