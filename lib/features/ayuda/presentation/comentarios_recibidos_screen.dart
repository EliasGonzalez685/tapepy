import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../data/comentario_service.dart';

/// Buzón completo de comentarios — solo lo puede ver el dueño de
/// plataforma (RLS de comentarios_app lo garantiza).
class ComentariosRecibidosScreen extends StatefulWidget {
  const ComentariosRecibidosScreen({super.key});

  @override
  State<ComentariosRecibidosScreen> createState() => _ComentariosRecibidosScreenState();
}

class _ComentariosRecibidosScreenState extends State<ComentariosRecibidosScreen> {
  final _service = ComentarioService();
  late Future<List<ComentarioItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarTodosLosComentarios();
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Comentarios de los usuarios')),
      body: FutureBuilder<List<ComentarioItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final comentarios = snapshot.data ?? [];
          if (comentarios.isEmpty) {
            return Center(
              child: Text('Todavía no hay comentarios.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (c.usuarioNombre != null)
                            _Chip(icono: Icons.person_outline, texto: c.usuarioNombre!),
                          if (c.organizacionNombre != null)
                            _Chip(icono: Icons.apartment_outlined, texto: c.organizacionNombre!),
                          _Chip(icono: Icons.schedule, texto: formatoFecha.format(c.creadoEn)),
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
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _Chip({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 14, color: AppTheme.rojoInstitucional),
        const SizedBox(width: 4),
        Text(texto,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
