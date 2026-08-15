import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../data/mensajeria_service.dart';

/// Hilo de ida y vuelta con una sola persona — se puede leer todo el
/// intercambio anterior y responder ahí mismo, como cualquier chat.
class ConversacionScreen extends StatefulWidget {
  final Usuario usuario;
  final String otroUsuarioId;
  final String otroNombre;
  final String? otroRolLabel;

  const ConversacionScreen({
    super.key,
    required this.usuario,
    required this.otroUsuarioId,
    required this.otroNombre,
    this.otroRolLabel,
  });

  @override
  State<ConversacionScreen> createState() => _ConversacionScreenState();
}

class _ConversacionScreenState extends State<ConversacionScreen> {
  final _service = MensajeriaService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late Future<List<MensajeHilo>> _future;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    _service.marcarConversacionLeida(usuarioId: widget.usuario.id, otroUsuarioId: widget.otroUsuarioId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _cargar() {
    _future = _service.cargarConversacion(usuarioId: widget.usuario.id, otroUsuarioId: widget.otroUsuarioId);
  }

  void _irAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await _future;
    _irAlFinal();
  }

  Future<void> _enviar() async {
    final organizacionId = widget.usuario.organizacionId;
    final texto = _controller.text;
    if (organizacionId == null || texto.trim().isEmpty) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await _service.enviarMensaje(
        organizacionId: organizacionId,
        de: widget.usuario.id,
        para: widget.otroUsuarioId,
        contenido: texto,
      );
      _controller.clear();
      await _refrescar();
    } on MensajeException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo enviar el mensaje. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.otroNombre),
            if (widget.otroRolLabel != null)
              Text(widget.otroRolLabel!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refrescar,
              child: FutureBuilder<List<MensajeHilo>>(
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
                  final mensajes = snapshot.data ?? [];
                  if (mensajes.isEmpty) {
                    return ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                          child: Column(
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  size: 44, color: Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 12),
                              Text('Todavía no hay mensajes con ${widget.otroNombre}. Escribí el primero.',
                                  textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  _irAlFinal();
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: mensajes.length,
                    itemBuilder: (context, index) => _Burbuja(mensaje: mensajes[index]),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLength: mensajeMaxCaracteres,
                          maxLines: 3,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: 'Escribí un mensaje...',
                            border: OutlineInputBorder(),
                            counterText: '',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _enviando
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton.filled(
                              onPressed: _controller.text.trim().isEmpty ? null : _enviar,
                              style: IconButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                              icon: const Icon(Icons.send, color: Colors.white),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  final MensajeHilo mensaje;
  const _Burbuja({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    final formatoHora = DateFormat('dd/MM HH:mm');
    final colorFondo = mensaje.esMio ? AppTheme.rojoInstitucional : Theme.of(context).colorScheme.surfaceContainerHighest;
    final colorTexto = mensaje.esMio ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final colorHora = mensaje.esMio ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant;

    return Align(
      alignment: mensaje.esMio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorFondo,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mensaje.esMio ? 16 : 4),
            bottomRight: Radius.circular(mensaje.esMio ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mensaje.contenido, style: TextStyle(color: colorTexto)),
            const SizedBox(height: 4),
            Text(formatoHora.format(mensaje.enviadoEn), style: TextStyle(color: colorHora, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
