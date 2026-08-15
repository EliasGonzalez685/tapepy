import '../../../core/config/supabase_config.dart';

class AsignarPresidenteAsociacionException implements Exception {
  final String message;
  AsignarPresidenteAsociacionException(this.message);
  @override
  String toString() => message;
}

/// Un miembro ya aprobado de la organización, candidato a ser asignado
/// como su presidente de asociación.
class MiembroCandidato {
  final String usuarioId;
  final String nombre;
  final String? cedula;
  final String? telefono;

  MiembroCandidato({
    required this.usuarioId,
    required this.nombre,
    this.cedula,
    this.telefono,
  });

  factory MiembroCandidato.fromMap(Map<String, dynamic> map) {
    return MiembroCandidato(
      usuarioId: map['id'] as String,
      nombre: map['nombre'] as String,
      cedula: map['cedula'] as String?,
      telefono: map['telefono'] as String?,
    );
  }
}

class PresidenteAsociacionInfo {
  final String usuarioId;
  final String nombre;
  final String? telefono;
  final String? email;

  PresidenteAsociacionInfo({
    required this.usuarioId,
    required this.nombre,
    this.telefono,
    this.email,
  });

  factory PresidenteAsociacionInfo.fromMap(Map<String, dynamic> map) {
    return PresidenteAsociacionInfo(
      usuarioId: map['id'] as String,
      nombre: map['nombre'] as String,
      telefono: map['telefono'] as String?,
      email: map['email'] as String?,
    );
  }
}

/// Gestión de quién es el presidente de asociación de una organización.
/// Solo el dueño de plataforma puede asignarlo o reemplazarlo (ver RPC
/// asignar_presidente_asociacion) — ni el propio presidente de
/// asociación tiene esa potestad sobre sí mismo, al revés de lo que
/// pasa con presidente de parada (que sí lo maneja la asociación).
class PresidenteAsociacionService {
  final _client = SupabaseConfig.client;

  /// null si esa organización todavía no tiene presidente asignado.
  Future<PresidenteAsociacionInfo?> cargarActual(String organizacionId) async {
    final row = await _client
        .from('usuarios')
        .select('id, nombre, telefono, email')
        .eq('organizacion_id', organizacionId)
        .eq('rol', 'presidente_asociacion')
        .maybeSingle();
    if (row == null) return null;
    return PresidenteAsociacionInfo.fromMap(row);
  }

  /// Miembros ya aprobados de la organización. Si alguno ya es el
  /// presidente actual, sigue apareciendo acá (rol pasa a
  /// 'presidente_asociacion' recién al asignarlo).
  Future<List<MiembroCandidato>> cargarCandidatos(String organizacionId) async {
    final rows = await _client
        .from('usuarios')
        .select('id, nombre, cedula, telefono')
        .eq('organizacion_id', organizacionId)
        .eq('cuenta_confirmada', true)
        .order('nombre');
    return (rows as List)
        .map((r) => MiembroCandidato.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Asigna (o reemplaza) el presidente de asociación. Si ya había
  /// alguien distinto, ese usuario vuelve a 'conductor' automáticamente
  /// (ver función asignar_presidente_asociacion).
  Future<void> asignarPresidente({
    required String organizacionId,
    required String usuarioId,
  }) async {
    try {
      await _client.rpc('asignar_presidente_asociacion', params: {
        'p_organizacion_id': organizacionId,
        'p_usuario_id': usuarioId,
      });
    } catch (_) {
      throw AsignarPresidenteAsociacionException(
        'No se pudo asignar el presidente. Intentá de nuevo.',
      );
    }
  }
}
