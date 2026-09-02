import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data/secretario_service.dart';

/// Cargo opcional de "secretario", uno por organización: solo lo asigna
/// (o quita) el presidente de asociación. Mientras alguien lo tenga,
/// gana los mismos permisos administrativos que el presidente -- no lo
/// reemplaza, es una ayuda extra por si el presidente no da abasto.
/// No es obligatorio tener uno.
class SecretarioScreen extends StatefulWidget {
  final String organizacionId;
  const SecretarioScreen({super.key, required this.organizacionId});

  @override
  State<SecretarioScreen> createState() => _SecretarioScreenState();
}

class _SecretarioScreenState extends State<SecretarioScreen> {
  final _service = SecretarioService();
  late Future<SecretarioActual?> _future;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _service.cargarActual(widget.organizacionId);
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await _future;
  }

  Future<void> _asignarOCambiar(SecretarioActual? actual) async {
    final cambiado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ElegirSecretarioSheet(
        organizacionId: widget.organizacionId,
        actualId: actual?.usuarioId,
      ),
    );
    if (cambiado == true) _refrescar();
  }

  Future<void> _quitar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Quitar el cargo de secretario?'),
        content: const Text(
          'La organización se queda sin secretario. Podés volver a asignar a alguien cuando quieras — no es obligatorio tener uno.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.estadoUrgente),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _service.quitarSecretario();
      if (!mounted) return;
      _refrescar();
    } on AsignarSecretarioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secretario')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<SecretarioActual?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final actual = snapshot.data;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'El secretario es un cargo opcional, uno solo por vez. '
                      'Podés elegir a cualquier socio ya aprobado -- un conductor de cualquier '
                      'parada, o un presidente de parada. Mientras tenga el cargo, va a tener '
                      'las mismas funciones que vos en la app, salvo esta pantalla.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (actual == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(Icons.badge_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          const Text(
                            'Todavía no asignaste un secretario.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _asignarOCambiar(null),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                            icon: const Icon(Icons.person_add_alt_outlined),
                            label: const Text('Asignar secretario'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: AppTheme.rojoInstitucional,
                                child: Icon(Icons.badge, color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(actual.nombre,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    Text(actual.rolLabel,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            )),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (actual.telefono != null || actual.email != null) ...[
                            const SizedBox(height: 12),
                            if (actual.telefono != null) Text('Tel: ${actual.telefono}'),
                            if (actual.email != null) Text(actual.email!),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _asignarOCambiar(actual),
                                  child: const Text('Cambiar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _quitar,
                                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.estadoUrgente),
                                  child: const Text('Quitar cargo'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ElegirSecretarioSheet extends StatefulWidget {
  final String organizacionId;
  final String? actualId;
  const _ElegirSecretarioSheet({required this.organizacionId, this.actualId});

  @override
  State<_ElegirSecretarioSheet> createState() => _ElegirSecretarioSheetState();
}

class _ElegirSecretarioSheetState extends State<_ElegirSecretarioSheet> {
  final _service = SecretarioService();
  late Future<List<MiembroCandidatoSecretario>> _future;
  String? _seleccionadoId;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarCandidatos(widget.organizacionId);
    _seleccionadoId = widget.actualId;
  }

  Future<void> _guardar() async {
    if (_seleccionadoId == null) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _service.asignarSecretario(_seleccionadoId!);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AsignarSecretarioException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo asignar el secretario. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
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
                widget.actualId != null ? 'Cambiar secretario' : 'Asignar secretario',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Elegí un conductor o presidente de parada ya aprobado.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<MiembroCandidatoSecretario>>(
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
                          'Todavía no hay socios aprobados en la organización.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      );
                    }
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
                          subtitle: Text(
                            candidato.cedula != null ? '${candidato.rolLabel} · CI ${candidato.cedula}' : candidato.rolLabel,
                          ),
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
