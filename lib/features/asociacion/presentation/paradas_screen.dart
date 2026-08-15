import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/asociacion_dashboard_service.dart';
import '../data/parada_resumen.dart';
import '../data/presidentes_parada_service.dart';

class _ParadasData {
  final List<ParadaResumen> paradas;
  final Map<String, PresidenteParadaItem> presidentes;
  _ParadasData({required this.paradas, required this.presidentes});
}

/// Gestión de paradas: crear nuevas, eliminar las que ya no hagan falta
/// y asignar (o reemplazar) el presidente de cada una — todo en un
/// mismo lugar, en vez de tener "Presidentes de parada" como pantalla
/// aparte.
class ParadasScreen extends StatefulWidget {
  final String organizacionId;
  const ParadasScreen({super.key, required this.organizacionId});

  @override
  State<ParadasScreen> createState() => _ParadasScreenState();
}

class _ParadasScreenState extends State<ParadasScreen> {
  final _service = AsociacionDashboardService();
  final _presidentesService = PresidentesParadaService();
  late Future<_ParadasData> _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<_ParadasData> _cargar() async {
    final resultados = await Future.wait([
      _service.cargarParadas(organizacionId: widget.organizacionId),
      _presidentesService.cargarListado(),
    ]);
    final paradas = resultados[0] as List<ParadaResumen>;
    final presidentesLista = resultados[1] as List<PresidenteParadaItem>;
    final presidentes = {for (final p in presidentesLista) p.paradaId: p};
    return _ParadasData(paradas: paradas, presidentes: presidentes);
  }

  Future<void> _refrescar() async {
    setState(() => _future = _cargar());
    await _future;
  }

  Future<void> _nuevaParada() async {
    final creada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _NuevaParadaSheet(organizacionId: widget.organizacionId),
    );
    if (creada == true) _refrescar();
  }

  Future<void> _eliminarParada(ParadaResumen parada) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar parada'),
        content: Text('¿Eliminar "${parada.nombre}"? Esta acción no se puede deshacer.'),
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
      await _service.eliminarParada(parada.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"${parada.nombre}" eliminada')));
      _refrescar();
    } on ParadaException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _asignarPresidente(ParadaResumen parada, PresidenteParadaItem? actual) async {
    final asignado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AsignarPresidenteSheet(
        paradaId: parada.id,
        paradaNombre: parada.nombre,
        presidenteActualId: actual?.presidenteId,
        presidenteActualNombre: actual?.presidenteNombre,
      ),
    );
    if (asignado == true) _refrescar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PARADAS DE LA ASOCIACIÓN')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevaParada,
        backgroundColor: AppTheme.rojoInstitucional,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined, color: Colors.white),
        label: const Text('Nueva parada', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<_ParadasData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudo cargar: ${snapshot.error}'),
                  ),
                ],
              );
            }
            final paradas = snapshot.data?.paradas ?? [];
            final presidentes = snapshot.data?.presidentes ?? {};
            if (paradas.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(Icons.signpost_outlined,
                            size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text('Todavía no hay paradas cargadas', textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        Text(
                          'Tocá "Nueva parada" para agregar la primera.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: paradas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final parada = paradas[index];
                final presidente = presidentes[parada.id];
                final tienePresidente = presidente?.tieneAsignado ?? false;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(
                              icono: Icons.location_pin,
                              color: parada.estado.color,
                              diametro: 46,
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
                                    '${parada.conductoresCount} conductores',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: Theme.of(context).colorScheme.error),
                              onPressed: () => _eliminarParada(parada),
                              tooltip: 'Eliminar parada',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              tienePresidente
                                  ? Icons.person_pin_circle_outlined
                                  : Icons.person_off_outlined,
                              size: 18,
                              color: tienePresidente
                                  ? AppTheme.rojoInstitucional
                                  : Colors.grey.shade500,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                tienePresidente
                                    ? 'Presidente: ${presidente!.presidenteNombre}'
                                    : 'Sin presidente asignado',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: tienePresidente
                                          ? Theme.of(context).colorScheme.onSurfaceVariant
                                          : Colors.grey.shade500,
                                      fontStyle:
                                          tienePresidente ? FontStyle.normal : FontStyle.italic,
                                    ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _asignarPresidente(parada, presidente),
                              icon: Icon(tienePresidente ? Icons.edit_outlined : Icons.add,
                                  size: 18),
                              label: Text(tienePresidente ? 'Editar' : 'Asignar'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.rojoInstitucional,
                              ),
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
      ),
    );
  }
}

/// Formulario mínimo para dar de alta una parada (nombre + ubicación
/// opcional).
class _NuevaParadaSheet extends StatefulWidget {
  final String organizacionId;
  const _NuevaParadaSheet({required this.organizacionId});

  @override
  State<_NuevaParadaSheet> createState() => _NuevaParadaSheetState();
}

class _NuevaParadaSheetState extends State<_NuevaParadaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _service = AsociacionDashboardService();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _nombreController.dispose();
    _ubicacionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _service.crearParada(
        organizacionId: widget.organizacionId,
        nombre: _nombreController.text.trim(),
        ubicacion: _ubicacionController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo crear la parada. Intentá de nuevo.');
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
            Text(
              'Nueva parada',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombreController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Ingresá un nombre' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ubicacionController,
              decoration: const InputDecoration(
                labelText: 'Ubicación (opcional)',
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Crear parada'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector de presidente de parada: lista los conductores ya
/// aprobados de esa parada para elegir quién queda como presidente. Si
/// ya había uno asignado, queda preseleccionado y se puede cambiar
/// (el anterior vuelve automáticamente a conductor).
class _AsignarPresidenteSheet extends StatefulWidget {
  final String paradaId;
  final String paradaNombre;
  final String? presidenteActualId;
  final String? presidenteActualNombre;

  const _AsignarPresidenteSheet({
    required this.paradaId,
    required this.paradaNombre,
    this.presidenteActualId,
    this.presidenteActualNombre,
  });

  @override
  State<_AsignarPresidenteSheet> createState() => _AsignarPresidenteSheetState();
}

class _AsignarPresidenteSheetState extends State<_AsignarPresidenteSheet> {
  final _service = PresidentesParadaService();
  late Future<List<ConductorCandidato>> _future;
  String? _seleccionadoId;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarConductoresElegibles(widget.paradaId);
  }

  Future<void> _guardar() async {
    if (_seleccionadoId == null) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _service.asignarPresidente(
        paradaId: widget.paradaId,
        usuarioId: _seleccionadoId!,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AsignarPresidenteException catch (e) {
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.presidenteActualNombre != null
                    ? 'Editar presidente de ${widget.paradaNombre}'
                    : 'Asignar presidente de ${widget.paradaNombre}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Elegí un conductor ya aprobado de esta parada.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<ConductorCandidato>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('No se pudo cargar: ${snapshot.error}'));
                    }
                    final candidatos = snapshot.data ?? [];
                    if (candidatos.isEmpty) {
                      return Center(
                        child: Text(
                          'Todavía no hay conductores aprobados en esta parada.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      );
                    }
                    _seleccionadoId ??= widget.presidenteActualId;
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: candidatos.length,
                      itemBuilder: (context, index) {
                        final candidato = candidatos[index];
                        return RadioListTile<String>(
                          value: candidato.usuarioId,
                          groupValue: _seleccionadoId,
                          activeColor: AppTheme.rojoInstitucional,
                          title: Text(candidato.nombre),
                          subtitle: candidato.cedula != null ? Text('CI ${candidato.cedula}') : null,
                          onChanged: (value) => setState(() => _seleccionadoId = value),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
              ],
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
          ),
        );
      },
    );
  }
}
