import '../../../core/config/supabase_config.dart';

/// Un comentario dejado por un usuario para el dueño de plataforma —
/// buzón simple de sugerencias, ver migración 0030.
class ComentarioItem {
  final String id;
  final String? usuarioNombre;
  final String? organizacionNombre;
  final String contenido;
  final DateTime creadoEn;

  ComentarioItem({
    required this.id,
    required this.contenido,
    required this.creadoEn,
    this.usuarioNombre,
    this.organizacionNombre,
  });

  factory ComentarioItem.fromMap(Map<String, dynamic> map) {
    final usuario = map['usuarios'] as Map<String, dynamic>?;
    final organizacion = map['organizaciones'] as Map<String, dynamic>?;
    return ComentarioItem(
      id: map['id'] as String,
      contenido: map['contenido'] as String,
      creadoEn: DateTime.parse(map['creado_en'] as String),
      usuarioNombre: usuario?['nombre'] as String?,
      organizacionNombre: organizacion?['nombre'] as String?,
    );
  }
}

/// Buzón de "Comentarios para mejorar la app" — cualquier usuario puede
/// dejar el suyo; solo el dueño de plataforma ve el buzón completo (RLS
/// lo garantiza, esto solo arma las consultas).
class ComentarioService {
  final _client = SupabaseConfig.client;

  Future<void> crearComentario({
    required String usuarioId,
    required String? organizacionId,
    required String contenido,
  }) async {
    await _client.from('comentarios_app').insert({
      'usuario_id': usuarioId,
      'organizacion_id': organizacionId,
      'contenido': contenido.trim(),
    });
  }

  /// Historial propio — cualquier usuario puede ver lo que él mismo
  /// mandó (no lo de otros).
  Future<List<ComentarioItem>> cargarMisComentarios(String usuarioId) async {
    final rows = await _client
        .from('comentarios_app')
        .select('id, contenido, creado_en')
        .eq('usuario_id', usuarioId)
        .order('creado_en', ascending: false);
    return (rows as List)
        .map((r) => ComentarioItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Buzón completo — solo el dueño de plataforma tiene permiso (RLS lo
  /// exige); para cualquier otro rol esta consulta simplemente devuelve
  /// solo sus propios comentarios.
  Future<List<ComentarioItem>> cargarTodosLosComentarios() async {
    final rows = await _client
        .from('comentarios_app')
        .select('id, contenido, creado_en, usuarios(nombre), organizaciones(nombre)')
        .order('creado_en', ascending: false);
    return (rows as List)
        .map((r) => ComentarioItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
