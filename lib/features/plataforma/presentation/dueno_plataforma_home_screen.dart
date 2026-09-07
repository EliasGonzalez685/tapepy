import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/menu_lateral.dart';
import '../../asociacion/presentation/asociacion_home_screen.dart';
import '../../asociacion/presentation/balance_general_screen.dart';
import '../data/presidente_asociacion_service.dart';
import '../data/solicitud_organizacion_service.dart';
import 'cuentas_bloqueadas_screen.dart';
import 'cuotas_plataforma_screen.dart';
import 'solicitudes_organizacion_screen.dart';

/// Home del dueño de plataforma (Elias): es prácticamente el mismo
/// panel que ve el presidente de asociación (paradas, solicitudes,
/// convenios, listados, firmas) de la organización que esté
/// supervisando — hoy solo existe Traude, pero esto se resuelve siempre
/// desde la base para cuando se sumen más clientes. La diferencia extra
/// es el control sobre QUIÉN es el presidente de esa asociación: ni el
/// propio presidente puede reasignarse a sí mismo, esa potestad es
/// exclusiva del dueño (ver PresidenteAsociacionService).
class DuenoPlataformaHomeScreen extends StatefulWidget {
  final Usuario? usuario;
  const DuenoPlataformaHomeScreen({super.key, this.usuario});

  @override
  State<DuenoPlataformaHomeScreen> createState() => _DuenoPlataformaHomeScreenState();
}

class _DuenoPlataformaHomeScreenState extends State<DuenoPlataformaHomeScreen> {
  final _organizacionService = OrganizacionService();
  final _solicitudOrganizacionService = SolicitudOrganizacionService();
  late Future<List<OrganizacionItem>> _future;
  OrganizacionItem? _seleccionada;
  int _solicitudesOrgPendientes = 0;

  @override
  void initState() {
    super.initState();
    _future = _organizacionService.cargarOrganizaciones();
    _cargarSolicitudesOrgPendientes();
  }

  Future<void> _cargarSolicitudesOrgPendientes() async {
    try {
      final pendientes = await _solicitudOrganizacionService.listarPendientes();
      if (mounted) setState(() => _solicitudesOrgPendientes = pendientes.length);
    } catch (_) {
      // Si falla, simplemente no se muestra el numerito -- no es crítico.
    }
  }

  /// Recarga la lista de organizaciones (por si se acaba de aprobar una
  /// nueva) y deja al dueño elegir sobre cuál pararse, ya que por
  /// defecto siempre queda la primera en orden alfabético.
  Future<void> _cambiarOrganizacion() async {
    final organizaciones = await _future;
    if (!mounted) return;
    final elegida = await showModalBottomSheet<OrganizacionItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SelectorOrganizacionSheet(
        organizaciones: organizaciones,
        seleccionadaId: _seleccionada?.id,
      ),
    );
    if (elegida != null && mounted) {
      setState(() => _seleccionada = elegida);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OrganizacionItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('No se pudo cargar: ${snapshot.error}')),
          );
        }
        final organizaciones = snapshot.data ?? [];
        if (organizaciones.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Todavía no hay ninguna organización cargada.')),
          );
        }
        _seleccionada ??= organizaciones.first;

        // El dueño de plataforma no pertenece a ninguna organización en
        // su propia fila (organizacion_id null a propósito) — para
        // reusar el panel de asociación tal cual, le pasamos un clon
        // suyo "parado" sobre la organización elegida.
        final usuarioComoAsociacion = widget.usuario?.copyWith(
          organizacionId: _seleccionada!.id,
        );

        return AsociacionHomeScreen(
          key: ValueKey(_seleccionada!.id),
          usuario: usuarioComoAsociacion,
          itemsExtraAdicionales: [
            ItemMenuLateral(
              icono: Icons.swap_horiz,
              titulo: 'Cambiar organización',
              onTap: () {
                Navigator.of(context).pop();
                _cambiarOrganizacion();
              },
            ),
            ItemMenuLateral(
              icono: Icons.domain_add_outlined,
              titulo: 'Solicitudes de organización',
              contador: _solicitudesOrgPendientes > 0 ? _solicitudesOrgPendientes : null,
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator
                    .push(
                      MaterialPageRoute(builder: (_) => const SolicitudesOrganizacionScreen()),
                    )
                    .then((_) {
                  _cargarSolicitudesOrgPendientes();
                  setState(() => _future = _organizacionService.cargarOrganizaciones());
                });
              },
            ),
            ItemMenuLateral(
              icono: Icons.admin_panel_settings_outlined,
              titulo: 'Presidente de asociación',
              onTap: () {
                final organizacion = _seleccionada!;
                final navigator = Navigator.of(context);
                navigator.pop();
                showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _AsignarPresidenteAsociacionSheet(
                    organizacionId: organizacion.id,
                    organizacionNombre: organizacion.nombre,
                  ),
                );
              },
            ),
            ItemMenuLateral(
              icono: Icons.lock_outline,
              titulo: 'Cuentas bloqueadas',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CuentasBloqueadasScreen()),
                );
              },
            ),
            ItemMenuLateral(
              icono: Icons.workspace_premium_outlined,
              titulo: 'Cuotas de plataforma',
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                if (widget.usuario == null) return;
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => CuotasPlataformaScreen(usuario: widget.usuario!),
                  ),
                );
              },
            ),
            ItemMenuLateral(
              icono: Icons.bar_chart_outlined,
              titulo: 'Balance general',
              onTap: () {
                final organizacionId = _seleccionada!.id;
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => BalanceGeneralScreen(organizacionId: organizacionId),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Selector de presidente de asociación: lista los miembros ya
/// aprobados de la organización para elegir quién queda como
/// presidente. Si ya había uno asignado, queda preseleccionado y se
/// puede cambiar (el anterior vuelve automáticamente a conductor).
class _AsignarPresidenteAsociacionSheet extends StatefulWidget {
  final String organizacionId;
  final String organizacionNombre;

  const _AsignarPresidenteAsociacionSheet({
    required this.organizacionId,
    required this.organizacionNombre,
  });

  @override
  State<_AsignarPresidenteAsociacionSheet> createState() =>
      _AsignarPresidenteAsociacionSheetState();
}

class _DatosPresidenteAsociacion {
  final PresidenteAsociacionInfo? actual;
  final List<MiembroCandidato> candidatos;
  _DatosPresidenteAsociacion({required this.actual, required this.candidatos});
}

class _AsignarPresidenteAsociacionSheetState extends State<_AsignarPresidenteAsociacionSheet> {
  final _service = PresidenteAsociacionService();
  late Future<_DatosPresidenteAsociacion> _future;
  String? _seleccionadoId;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<_DatosPresidenteAsociacion> _cargar() async {
    final resultados = await Future.wait([
      _service.cargarActual(widget.organizacionId),
      _service.cargarCandidatos(widget.organizacionId),
    ]);
    return _DatosPresidenteAsociacion(
      actual: resultados[0] as PresidenteAsociacionInfo?,
      candidatos: resultados[1] as List<MiembroCandidato>,
    );
  }

  Future<void> _guardar() async {
    if (_seleccionadoId == null) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _service.asignarPresidente(
        organizacionId: widget.organizacionId,
        usuarioId: _seleccionadoId!,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AsignarPresidenteAsociacionException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo asignar el presidente. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: FutureBuilder<_DatosPresidenteAsociacion>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('No se pudo cargar: ${snapshot.error}'));
              }
              final datos = snapshot.data!;
              _seleccionadoId ??= datos.actual?.usuarioId;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    datos.actual != null
                        ? 'Editar presidente de ${widget.organizacionNombre}'
                        : 'Asignar presidente de ${widget.organizacionNombre}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Elegí un miembro ya aprobado de la organización.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: datos.candidatos.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'Todavía no hay miembros aprobados en esta organización.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            controller: scrollController,
                            itemCount: datos.candidatos.length,
                            itemBuilder: (context, index) {
                              final candidato = datos.candidatos[index];
                              return RadioListTile<String>(
                                value: candidato.usuarioId,
                                groupValue: _seleccionadoId,
                                activeColor: AppTheme.rojoInstitucional,
                                title: Text(candidato.nombre),
                                subtitle:
                                    candidato.cedula != null ? Text('CI ${candidato.cedula}') : null,
                                onChanged: (value) => setState(() => _seleccionadoId = value),
                              );
                            },
                          ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: (_guardando || _seleccionadoId == null) ? null : _guardar,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                    child: _guardando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Guardar'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Lista simple para que el dueño de plataforma elija sobre qué
/// organización pararse a administrar -- necesario porque por defecto
/// siempre queda la primera en orden alfabético, y una organización
/// recién aprobada (ver SolicitudesOrganizacionScreen) puede no serlo.
class _SelectorOrganizacionSheet extends StatelessWidget {
  final List<OrganizacionItem> organizaciones;
  final String? seleccionadaId;

  const _SelectorOrganizacionSheet({
    required this.organizaciones,
    required this.seleccionadaId,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Elegí la organización',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: organizaciones.length,
                itemBuilder: (context, index) {
                  final org = organizaciones[index];
                  return RadioListTile<String>(
                    value: org.id,
                    groupValue: seleccionadaId,
                    activeColor: AppTheme.rojoInstitucional,
                    title: Text(org.nombre),
                    onChanged: (_) => Navigator.of(context).pop(org),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
