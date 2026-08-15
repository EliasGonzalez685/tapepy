import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../auth/data/registro_service.dart';
import '../data/conductor_service.dart';
import 'mi_vehiculo_screen.dart';
import 'mis_cuotas_screen.dart';
import 'mis_documentos_screen.dart';

/// Todo presidente (de parada o de asociación) es, además de su rol de
/// representación, socio de una parada como cualquier conductor — tiene
/// su propio vehículo y sus propios documentos para el mismo control
/// que se le pide al resto. Esta pantalla es el equivalente de "Mi
/// actividad" del panel del conductor, pero reusable desde el panel de
/// presidente de parada y el de presidente de asociación.
///
/// Si todavía no tiene fila en `conductores` (ej. una cuenta de
/// presidente de asociación creada directamente, sin pasar antes por
/// conductor), primero hay que activarle ese perfil eligiendo una
/// parada. Si viene de un presidente de parada, [paradaIdSugerida] ya
/// trae su propia parada — ahí no hace falta elegir nada.
class MiPerfilSocioScreen extends StatefulWidget {
  final Usuario usuario;
  final String? paradaIdSugerida;
  final String? paradaNombreSugerida;
  const MiPerfilSocioScreen({
    super.key,
    required this.usuario,
    this.paradaIdSugerida,
    this.paradaNombreSugerida,
  });

  @override
  State<MiPerfilSocioScreen> createState() => _MiPerfilSocioScreenState();
}

class _MiPerfilSocioScreenState extends State<MiPerfilSocioScreen> {
  final _conductorService = ConductorService();
  final _registroService = RegistroService();
  late Future<ConductorPerfil?> _future;
  Future<List<ParadaOpcion>>? _futureParadas;
  ParadaOpcion? _paradaElegida;
  bool _activando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    if (widget.paradaIdSugerida == null && widget.usuario.organizacionId != null) {
      _futureParadas = _registroService.cargarParadas(widget.usuario.organizacionId!);
    }
  }

  void _cargar() {
    _future = _conductorService.cargarPerfil(widget.usuario.id);
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await _future;
  }

  Future<void> _activar(String paradaId) async {
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId == null) return;
    setState(() => _activando = true);
    try {
      await _conductorService.crearPerfilPropio(
        organizacionId: organizacionId,
        paradaId: paradaId,
        usuarioId: widget.usuario.id,
      );
      await _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo activar tu perfil. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _activando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil de socio')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<ConductorPerfil?>(
          future: _future,
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
            final perfil = snapshot.data;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (perfil == null)
                  _ActivarPerfil(
                    paradaIdSugerida: widget.paradaIdSugerida,
                    paradaNombreSugerida: widget.paradaNombreSugerida,
                    futureParadas: _futureParadas,
                    paradaElegida: _paradaElegida,
                    onElegirParada: (p) => setState(() => _paradaElegida = p),
                    activando: _activando,
                    onActivar: () {
                      final id = widget.paradaIdSugerida ?? _paradaElegida?.id;
                      if (id != null) _activar(id);
                    },
                  )
                else ...[
                  _AccesoCard(
                    icono: Icons.directions_car_filled_outlined,
                    color: AppTheme.rojoInstitucional,
                    titulo: 'Mis vehículos',
                    subtitulo: perfil.resumenVehiculos,
                    onTap: () async {
                      await Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => MiVehiculoScreen(perfil: perfil)));
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
                        builder: (_) => MisDocumentosScreen(perfil: perfil, usuarioId: widget.usuario.id))),
                  ),
                  const SizedBox(height: 10),
                  _AccesoCard(
                    icono: Icons.payments_outlined,
                    color: AppTheme.estadoOk,
                    titulo: 'Mis pagos',
                    subtitulo: 'Estado de tus pagos mensuales',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => MisCuotasScreen(usuario: widget.usuario))),
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

class _ActivarPerfil extends StatelessWidget {
  final String? paradaIdSugerida;
  final String? paradaNombreSugerida;
  final Future<List<ParadaOpcion>>? futureParadas;
  final ParadaOpcion? paradaElegida;
  final void Function(ParadaOpcion?) onElegirParada;
  final bool activando;
  final VoidCallback onActivar;

  const _ActivarPerfil({
    required this.paradaIdSugerida,
    required this.paradaNombreSugerida,
    required this.futureParadas,
    required this.paradaElegida,
    required this.onElegirParada,
    required this.activando,
    required this.onActivar,
  });

  @override
  Widget build(BuildContext context) {
    final puedeActivar = paradaIdSugerida != null || paradaElegida != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(
                    icono: Icons.badge_outlined, color: AppTheme.rojoInstitucional, diametro: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Activá tu perfil de socio',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Como presidente también sos socio de una parada, con tu propio vehículo y '
              'tus propios documentos — el mismo control que se le pide a cualquier conductor.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            if (paradaIdSugerida != null)
              FilledButton(
                onPressed: activando ? null : onActivar,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                child: activando
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Activar mi perfil en ${paradaNombreSugerida ?? 'mi parada'}'),
              )
            else
              FutureBuilder<List<ParadaOpcion>>(
                future: futureParadas,
                builder: (context, snapshot) {
                  final paradas = snapshot.data ?? [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<ParadaOpcion>(
                        value: paradaElegida,
                        decoration:
                            const InputDecoration(labelText: 'Tu parada', border: OutlineInputBorder()),
                        items: paradas
                            .map((p) => DropdownMenuItem(value: p, child: Text(p.nombre)))
                            .toList(),
                        onChanged: onElegirParada,
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: (activando || !puedeActivar) ? null : onActivar,
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                        child: activando
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Activar mi perfil'),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
