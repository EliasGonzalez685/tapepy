import '../../core/config/supabase_config.dart';
import '../models/user_role.dart';

/// Un miembro de la organización con su estado "en servicio" — usado
/// tanto en el listado por parada (presidente de parada) como en el
/// listado global de la organización (presidente de asociación).
class MiembroActivoItem {
  final String usuarioId;
  final String nombre;
  final UserRole rol;
  final bool enServicio;
  final String? paradaNombre;

  MiembroActivoItem({
    required this.usuarioId,
    required this.nombre,
    required this.rol,
    required this.enServicio,
    this.paradaNombre,
  });
}

/// Bandera de autoservicio "en servicio" (activo/trabajando ahora):
/// la prende o apaga cada usuario sobre su propia fila — conductores y
/// también los presidentes, de parada y de asociación. La RLS ya
/// restringe la escritura a `id = auth.uid()`, así que este servicio
/// no necesita validar nada más.
class EstadoServicioService {
  final _client = SupabaseConfig.client;

  Future<void> actualizar(String usuarioId, bool enServicio) async {
    await _client.from('usuarios').update({'en_servicio': enServicio}).eq('id', usuarioId);
  }

  /// Todos los miembros confirmados de la organización (conductores y
  /// presidentes de parada) con su estado en_servicio y a qué parada
  /// pertenecen. Lo usa el presidente de asociación, que ve de todos.
  Future<List<MiembroActivoItem>> cargarMiembrosOrganizacion(String organizacionId) async {
    final usuarios = await _client
        .from('usuarios')
        .select('id, nombre, rol, en_servicio')
        .eq('organizacion_id', organizacionId)
        .eq('cuenta_confirmada', true)
        .inFilter('rol', ['conductor', 'presidente_parada'])
        .order('nombre');

    final conductoresRows = await _client
        .from('conductores')
        .select('usuario_id, paradas(nombre)')
        .eq('organizacion_id', organizacionId);

    final paradasPresidentes = await _client
        .from('paradas')
        .select('presidente_id, nombre')
        .eq('organizacion_id', organizacionId)
        .not('presidente_id', 'is', null);

    final paradaPorConductor = <String, String>{};
    for (final row in conductoresRows as List) {
      final map = row as Map<String, dynamic>;
      final parada = map['paradas'] as Map<String, dynamic>?;
      final nombre = parada?['nombre'] as String?;
      if (nombre != null) paradaPorConductor[map['usuario_id'] as String] = nombre;
    }

    final paradaPorPresidente = <String, String>{};
    for (final row in paradasPresidentes as List) {
      final map = row as Map<String, dynamic>;
      final presidenteId = map['presidente_id'] as String?;
      final nombre = map['nombre'] as String?;
      if (presidenteId != null && nombre != null) paradaPorPresidente[presidenteId] = nombre;
    }

    return (usuarios as List).map((r) {
      final map = r as Map<String, dynamic>;
      final id = map['id'] as String;
      final rol = UserRole.fromString(map['rol'] as String);
      return MiembroActivoItem(
        usuarioId: id,
        nombre: map['nombre'] as String? ?? 'Sin nombre',
        rol: rol,
        enServicio: map['en_servicio'] as bool? ?? false,
        paradaNombre: rol == UserRole.conductor ? paradaPorConductor[id] : paradaPorPresidente[id],
      );
    }).toList();
  }
}
