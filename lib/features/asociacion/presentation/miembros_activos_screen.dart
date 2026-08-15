import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/estado_servicio_service.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/widgets/badge_en_servicio.dart';
import '../../../shared/widgets/icon_badge.dart';

/// Listado global de miembros de la organización (conductores y
/// presidentes de parada) con su bandera "en servicio" — cada uno la
/// prende o apaga sobre sí mismo, acá el presidente de asociación solo
/// consulta. A diferencia del presidente de parada, que ve solo los
/// miembros de SU parada, acá se ven todos.
class MiembrosActivosScreen extends StatefulWidget {
  final String organizacionId;
  const MiembrosActivosScreen({super.key, required this.organizacionId});

  @override
  State<MiembrosActivosScreen> createState() => _MiembrosActivosScreenState();
}

class _MiembrosActivosScreenState extends State<MiembrosActivosScreen> {
  final _service = EstadoServicioService();
  late Future<List<MiembroActivoItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarMiembrosOrganizacion(widget.organizacionId);
  }

  void _refrescar() => setState(() {
        _future = _service.cargarMiembrosOrganizacion(widget.organizacionId);
      });

  String _labelRol(UserRole rol) {
    switch (rol) {
      case UserRole.presidenteParada:
        return 'Presidente de parada';
      case UserRole.conductor:
        return 'Conductor';
      default:
        return rol.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Miembros activos')),
      body: RefreshIndicator(
        onRefresh: () async {
          _refrescar();
          await _future;
        },
        child: FutureBuilder<List<MiembroActivoItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                        const SizedBox(height: 12),
                        const Text('No se pudo cargar. Deslizá para reintentar.',
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              );
            }
            final miembros = [...(snapshot.data ?? [])];
            if (miembros.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(Icons.groups_outlined,
                            size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text('Todavía no hay miembros aprobados en esta organización.',
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              );
            }
            miembros.sort((a, b) {
              if (a.enServicio != b.enServicio) return a.enServicio ? -1 : 1;
              return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
            });
            final activos = miembros.where((m) => m.enServicio).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
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
                          '$activos de ${miembros.length} miembros en servicio ahora',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ...miembros.map((m) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            IconBadge(
                              icono: m.rol == UserRole.presidenteParada
                                  ? Icons.workspace_premium_outlined
                                  : Icons.person,
                              color: m.enServicio ? AppTheme.estadoOk : Colors.grey.shade400,
                              diametro: 44,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.nombre,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      _labelRol(m.rol),
                                      if (m.paradaNombre != null) m.paradaNombre!,
                                    ].join(' · '),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            BadgeEnServicio(enServicio: m.enServicio),
                          ],
                        ),
                      ),
                    )),
              ],
            );
          },
        ),
      ),
    );
  }
}
