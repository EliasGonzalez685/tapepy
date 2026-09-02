import '../../../core/config/supabase_config.dart';

class AsignarSecretarioException implements Exception {
  final String message;
  AsignarSecretarioException(this.message);
  @override
  String toString() => message;
}

/// Un miembro de la organización (conductor o presidente de parada),
/// candidato a ser nombrado secretario. El propio presidente de
/// asociación no aparece: ya tiene esas funciones por su cargo.
class MiembroCandidatoSecretario {
  final String usuarioId;
  final String nombre;
  final String? cedula;
  final String rolLabel;

  MiembroCandidatoSecretario({
    required this.usuarioId,
    required this.nombre,
    required this.rolLabel,
    this.cedula,
  });

  factory MiembroCandidatoSecretario.fromMap(Map<String, dynamic> map) {
    return MiembroCandidatoSecretario(
      usuarioId: map['id'] as String,
      nombre: map['nombre'] as String,
      cedula: map['cedula'] as String?,
      rolLabel: switch (map['rol'] as String) {
        'presidente_parada' => 'Presidente de parada',
        _ => 'Conductor',
      },
    );
  }
}

class SecretarioActual {
  final String usuarioId;
  final String nombre;
  final String? telefono;
  final String? email;
  final String rolLabel;

  SecretarioActual({
    required this.usuarioId,
    required this.nombre,
    required this.rolLabel,
    this.telefono,
    this.email,
  });

  factory SecretarioActual.fromMap(Map<String, dynamic> map) {
    return SecretarioActual(
      usuarioId: map['id'] as String,
      nombre: map['nombre'] as String,
      telefono: map['telefono'] as String?,
      email: map['email'] as String?,
      rolLabel: switch (map['rol'] as String) {
        'presidente_parada' => 'Presidente de parada',
        _ => 'Conductor',
      },
    );
  }
}

/// Cargo opcional de "secretario": uno por organización, elegido por el
/// presidente de asociación entre cualquier miembro ya aprobado (un
/// conductor de cualquier parada, o un presidente de parada). Mientras
/// dure el cargo, esa persona tiene los mismos permisos administrativos
/// que el presidente — ver auth_es_presidente_asociacion() en la base.
class SecretarioService {
  final _client = SupabaseConfig.client;

  Future<SecretarioActual?> cargarActual(String organizacionId) async {
    final row = await _client
        .from('usuarios')
        .select('id, nombre, telefono, email, rol')
        .eq('organizacion_id', organizacionId)
        .eq('es_secretario', true)
        .maybeSingle();
    return row == null ? null : SecretarioActual.fromMap(row);
  }

  /// Miembros aprobados de la organización, sin contar al presidente de
  /// asociación (ya tiene estas funciones) ni al dueño de plataforma.
  Future<List<MiembroCandidatoSecretario>> cargarCandidatos(String organizacionId) async {
    final rows = await _client
        .from('usuarios')
        .select('id, nombre, cedula, rol')
        .eq('organizacion_id', organizacionId)
        .eq('cuenta_confirmada', true)
        .neq('rol', 'presidente_asociacion')
        .order('nombre');
    return (rows as List)
        .map((r) => MiembroCandidatoSecretario.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Asigna (o reemplaza) al secretario de la organización. Si ya había
  /// alguien distinto, pierde el cargo automáticamente (ver función
  /// asignar_secretario).
  Future<void> asignarSecretario(String usuarioId) async {
    try {
      await _client.rpc('asignar_secretario', params: {'p_usuario_id': usuarioId});
    } catch (_) {
      throw AsignarSecretarioException('No se pudo asignar el secretario. Intentá de nuevo.');
    }
  }

  /// Deja a la organización sin secretario (no es obligatorio tener uno).
  Future<void> quitarSecretario() async {
    try {
      await _client.rpc('quitar_secretario');
    } catch (_) {
      throw AsignarSecretarioException('No se pudo quitar el secretario. Intentá de nuevo.');
    }
  }
}
