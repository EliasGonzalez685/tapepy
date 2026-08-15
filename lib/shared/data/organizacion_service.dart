import '../../core/config/supabase_config.dart';

class OrganizacionItem {
  final String id;
  final String nombre;
  OrganizacionItem({required this.id, required this.nombre});
}

/// Nombre de la organización (ej. "Traude") para mostrar en el AppBar
/// en vez de la marca de la plataforma — cada organización/cliente ve
/// su propio nombre, no "TapePy".
class OrganizacionService {
  final _client = SupabaseConfig.client;

  Future<String?> cargarNombre(String organizacionId) async {
    final row = await _client
        .from('organizaciones')
        .select('nombre')
        .eq('id', organizacionId)
        .maybeSingle();
    return row?['nombre'] as String?;
  }

  /// Todas las organizaciones activas — el dueño de plataforma no
  /// pertenece a ninguna en particular (ve todas). Hoy solo existe
  /// Traude, pero esto nunca debe asumir cuál: se resuelve siempre desde
  /// la base para cuando se sumen más clientes.
  Future<List<OrganizacionItem>> cargarOrganizaciones() async {
    final rows = await _client
        .from('organizaciones')
        .select('id, nombre')
        .eq('activo', true)
        .order('nombre');
    return (rows as List)
        .map((r) => OrganizacionItem(
              id: r['id'] as String,
              nombre: r['nombre'] as String,
            ))
        .toList();
  }
}
