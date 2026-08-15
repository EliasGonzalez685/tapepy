import '../../core/config/supabase_config.dart';

class OrganizacionItem {
  final String id;
  final String nombre;
  OrganizacionItem({required this.id, required this.nombre});
}

/// Datos de contacto del presidente de asociación — para el Centro de
/// ayuda, donde cualquier socio necesita saber a quién escribirle.
class ContactoPresidente {
  final String nombre;
  final String? telefono;
  final String? email;
  ContactoPresidente({required this.nombre, this.telefono, this.email});
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

  /// null si la organización todavía no tiene presidente de asociación
  /// asignado. Cualquier usuario de la misma organización puede leer
  /// esto (RLS de `usuarios` ya permite ver a los demás socios de la
  /// propia organización) — se usa en el Centro de ayuda.
  Future<ContactoPresidente?> cargarPresidenteAsociacion(String organizacionId) async {
    final rows = await _client
        .from('usuarios')
        .select('nombre, telefono, email')
        .eq('organizacion_id', organizacionId)
        .eq('rol', 'presidente_asociacion')
        .limit(1);
    final lista = rows as List;
    if (lista.isEmpty) return null;
    final row = lista.first as Map<String, dynamic>;
    return ContactoPresidente(
      nombre: row['nombre'] as String,
      telefono: row['telefono'] as String?,
      email: row['email'] as String?,
    );
  }
}
