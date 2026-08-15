import '../../../core/config/supabase_config.dart';

class AsignarPresidenteException implements Exception {
  final String message;
  AsignarPresidenteException(this.message);
  @override
  String toString() => message;
}

/// Un conductor de la parada, candidato a ser asignado como su
/// presidente.
class ConductorCandidato {
  final String usuarioId;
  final String nombre;
  final String? cedula;
  final String? telefono;

  ConductorCandidato({
    required this.usuarioId,
    required this.nombre,
    this.cedula,
    this.telefono,
  });

  factory ConductorCandidato.fromMap(Map<String, dynamic> map) {
    final usuario = map['usuarios'] as Map<String, dynamic>;
    return ConductorCandidato(
      usuarioId: usuario['id'] as String,
      nombre: usuario['nombre'] as String,
      cedula: usuario['cedula'] as String?,
      telefono: usuario['telefono'] as String?,
    );
  }
}

class PresidenteParadaItem {
  final String paradaId;
  final String paradaNombre;
  final String? paradaUbicacion;
  final String? presidenteId;
  final String? presidenteNombre;
  final String? presidenteTelefono;
  final String? presidenteEmail;

  PresidenteParadaItem({
    required this.paradaId,
    required this.paradaNombre,
    this.paradaUbicacion,
    this.presidenteId,
    this.presidenteNombre,
    this.presidenteTelefono,
    this.presidenteEmail,
  });

  bool get tieneAsignado => presidenteNombre != null;

  factory PresidenteParadaItem.fromMap(Map<String, dynamic> map) {
    final presidente = map['usuarios'] as Map<String, dynamic>?;
    return PresidenteParadaItem(
      paradaId: map['id'] as String,
      paradaNombre: map['nombre'] as String,
      paradaUbicacion: map['ubicacion'] as String?,
      presidenteId: presidente?['id'] as String?,
      presidenteNombre: presidente?['nombre'] as String?,
      presidenteTelefono: presidente?['telefono'] as String?,
      presidenteEmail: presidente?['email'] as String?,
    );
  }
}

/// Listado de paradas de la organización junto con su presidente de
/// parada asignado (si tiene), y la asignación/reemplazo de ese
/// presidente desde el propio panel de "Paradas".
class PresidentesParadaService {
  final _client = SupabaseConfig.client;

  Future<List<PresidenteParadaItem>> cargarListado() async {
    final rows = await _client
        .from('paradas')
        .select('id, nombre, ubicacion, usuarios(id, nombre, telefono, email)')
        .order('nombre');
    return (rows as List)
        .map((r) => PresidenteParadaItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Conductores ya aprobados de esa parada, candidatos a ser su
  /// presidente. Si alguno de ellos ya es el presidente actual, sigue
  /// apareciendo acá (rol pasa a 'presidente_parada' recién al asignarlo).
  Future<List<ConductorCandidato>> cargarConductoresElegibles(String paradaId) async {
    final rows = await _client
        .from('conductores')
        .select('usuarios!inner(id, nombre, cedula, telefono, cuenta_confirmada)')
        .eq('parada_id', paradaId)
        .eq('usuarios.cuenta_confirmada', true);
    final items = (rows as List)
        .map((r) => ConductorCandidato.fromMap(r as Map<String, dynamic>))
        .toList();
    items.sort((a, b) => a.nombre.compareTo(b.nombre));
    return items;
  }

  /// Asigna (o reemplaza) el presidente de una parada. Si ya había
  /// alguien distinto, ese usuario vuelve a 'conductor' automáticamente
  /// (ver función asignar_presidente_parada).
  Future<void> asignarPresidente({
    required String paradaId,
    required String usuarioId,
  }) async {
    try {
      await _client.rpc('asignar_presidente_parada', params: {
        'p_parada_id': paradaId,
        'p_usuario_id': usuarioId,
      });
    } catch (_) {
      throw AsignarPresidenteException(
        'No se pudo asignar el presidente. Intentá de nuevo.',
      );
    }
  }
}
