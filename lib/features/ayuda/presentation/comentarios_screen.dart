import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../data/comentario_service.dart';

/// "Comentarios para mejorar la app" — cualquier usuario puede dejar un
/// comentario que solo el dueño de plataforma va a leer (ver
/// ComentariosRecibidosScreen). También muestra el historial de lo que
/// el propio usuario ya mandó.
class ComentariosScreen extends StatefulWidget {
  final Usuario usuario;
  const ComentariosScreen({super.key, required this.usuario});

  @override
  State<ComentariosScreen> createState() => _ComentariosScreenState();
}

class _ComentariosScreenState extends State<ComentariosScreen> {
  final _service = ComentarioService();
  final _controller = TextEditingController();
  late Future<List<ComentarioItem>> _future;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _service.cargarMisComentarios(widget.usuario.id);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      await _service.crearComentario(
        usuarioId: widget.usuario.id,
        organizacionId: widget.usuario.organizacionId,
        contenido: texto,
      );
      _controller.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('¡Gracias! Tu comentario fue enviado.')));
      setState(_cargar);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo enviar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Comentarios para mejorar la app')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Contanos qué te gustaría que mejoremos o agreguemos. Tu '
                  'comentario lo va a leer el responsable de la plataforma.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Escribí tu comentario o sugerencia...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _enviando ? null : _enviar,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                  child: _enviando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enviar comentario'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Tus comentarios anteriores',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ComentarioItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final comentarios = snapshot.data ?? [];
                if (comentarios.isEmpty) {
                  return Center(
                    child: Text('Todavía no mandaste ningún comentario.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: comentarios.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final c = comentarios[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.contenido),
                            const SizedBox(height: 6),
                            Text(formatoFecha.format(c.creadoEn),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
