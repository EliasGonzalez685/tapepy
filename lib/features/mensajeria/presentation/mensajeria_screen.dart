import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/mensajeria_service.dart';
import 'conversacion_screen.dart';

/// Lista de conversaciones: una fila por cada persona con la que hay
/// intercambio, con el último mensaje y cuántos quedaron sin leer. Para
/// responder o seguir hablando se entra al hilo (ConversacionScreen) —
/// acá solo se elige con quién.
class MensajeriaScreen extends StatefulWidget {
  final Usuario usuario;
  const MensajeriaScreen({super.key, required this.usuario});

  @override
  State<MensajeriaScreen> createState() => _MensajeriaScreenState();
}

class _MensajeriaScreenState extends State<MensajeriaScreen> {
  final _service = MensajeriaService();
  late Future<List<ConversacionResumen>> _future;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _service.cargarConversaciones(widget.usuario.id);
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await _future;
  }

  Future<void> _abrirConversacion({
    required String otroUsuarioId,
    required String otroNombre,
    String? otroRolLabel,
  }) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversacionScreen(
        usuario: widget.usuario,
        otroUsuarioId: otroUsuarioId,
        otroNombre: otroNombre,
        otroRolLabel: otroRolLabel,
      ),
    ));
    if (mounted) _refrescar();
  }

  Future<void> _abrirNuevaConversacion() async {
    final destinatario = await showModalBottomSheet<DestinatarioItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ElegirDestinatarioSheet(usuario: widget.usuario),
    );
    if (destinatario == null) return;
    if (!mounted) return;
    _abrirConversacion(
      otroUsuarioId: destinatario.usuarioId,
      otroNombre: destinatario.nombre,
      otroRolLabel: destinatario.rolLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajería')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNuevaConversacion,
        backgroundColor: AppTheme.rojoInstitucional,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_outlined, color: Colors.white),
        label: const Text('Nuevo mensaje', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<ConversacionResumen>>(
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
            final conversaciones = snapshot.data ?? [];
            if (conversaciones.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Column(
                      children: [
                        Icon(Icons.mail_outline,
                            size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text('Todavía no tenés conversaciones'),
                      ],
                    ),
                  ),
                ],
              );
            }
            final formatoFecha = DateFormat('dd/MM');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: conversaciones.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final c = conversaciones[index];
                final haySinLeer = c.noLeidos > 0;
                final previa = c.ultimoEsMio ? 'Vos: ${c.ultimoMensaje}' : c.ultimoMensaje;
                return Card(
                  color: haySinLeer ? AppTheme.rojoInstitucional.withValues(alpha: 0.04) : null,
                  child: ListTile(
                    onTap: () => _abrirConversacion(
                      otroUsuarioId: c.otroUsuarioId,
                      otroNombre: c.otroNombre,
                      otroRolLabel: c.otroRolLabel,
                    ),
                    leading: IconBadge(
                      icono: Icons.person_outline,
                      color: haySinLeer ? AppTheme.rojoInstitucional : Colors.grey,
                      diametro: 42,
                    ),
                    title: Text(
                      c.otroNombre,
                      style: TextStyle(fontWeight: haySinLeer ? FontWeight.bold : FontWeight.normal),
                    ),
                    subtitle: Text(
                      previa,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: haySinLeer ? FontWeight.w600 : FontWeight.normal),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatoFecha.format(c.ultimoEnviadoEn),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                        if (haySinLeer) ...[
                          const SizedBox(height: 4),
                          CircleAvatar(
                            radius: 9,
                            backgroundColor: AppTheme.rojoInstitucional,
                            child: Text('${c.noLeidos}',
                                style: const TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ],
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

/// Elegir con quién empezar una conversación nueva (según lo que le
/// toque al rol del usuario logueado — ver
/// MensajeriaService.cargarDestinatariosPosibles). Acá solo se elige la
/// persona; el mensaje en sí se escribe ya dentro del hilo.
class _ElegirDestinatarioSheet extends StatefulWidget {
  final Usuario usuario;
  const _ElegirDestinatarioSheet({required this.usuario});

  @override
  State<_ElegirDestinatarioSheet> createState() => _ElegirDestinatarioSheetState();
}

class _ElegirDestinatarioSheetState extends State<_ElegirDestinatarioSheet> {
  final _service = MensajeriaService();
  late Future<List<DestinatarioItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarDestinatariosPosibles(widget.usuario);
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: FutureBuilder<List<DestinatarioItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('No se pudo cargar: ${snapshot.error}'));
              }
              final destinatarios = snapshot.data ?? [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Nuevo mensaje',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Elegí a quién escribirle.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (destinatarios.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Todavía no hay a quién escribirle desde tu cuenta.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        controller: scrollController,
                        itemCount: destinatarios.length,
                        itemBuilder: (context, index) {
                          final d = destinatarios[index];
                          return ListTile(
                            leading: const IconBadge(
                                icono: Icons.person_outline, color: AppTheme.rojoInstitucional, diametro: 40),
                            title: Text(d.nombre),
                            subtitle: Text(d.rolLabel),
                            onTap: () => Navigator.of(context).pop(d),
                          );
                        },
                      ),
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
