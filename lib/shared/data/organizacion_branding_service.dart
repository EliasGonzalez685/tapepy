import '../../core/config/supabase_config.dart';
import '../models/organizacion_branding.dart';
import '../models/tipo_organizacion.dart';

/// Carga la identidad visual (nombre, logo, color) de las
/// organizaciones. La tabla `organizaciones` tiene una política RLS
/// pública para filas activas, así que esto funciona tanto antes de
/// iniciar sesión (selección de organización, login) como después
/// (carnet, constancias, listados).
///
/// Cachea en memoria: son datos que casi no cambian durante una
/// sesión y se piden desde varias pantallas distintas.
class OrganizacionBrandingService {
  final _client = SupabaseConfig.client;

  static final Map<String, OrganizacionBranding> _cachePorId = {};
  static List<OrganizacionBranding>? _cacheActivas;

  static const _columnas = 'id, nombre, nombre_completo, tagline, logo_asset, '
      'color_primario, carnet_subtitulo, mostrar_banderas_frontera, '
      'membrete_legal, telefono_membrete, url_verificacion_carnet, tipo';

  /// Todas las organizaciones activas, para pantallas previas al login
  /// (selección de organización) o el selector de registro.
  Future<List<OrganizacionBranding>> listarActivas({bool forzar = false}) async {
    if (!forzar && _cacheActivas != null) return _cacheActivas!;
    final rows = await _client
        .from('organizaciones')
        .select(_columnas)
        .eq('activo', true)
        .order('nombre');
    final resultado = (rows as List)
        .map((r) => OrganizacionBranding.fromMap(r as Map<String, dynamic>))
        .toList();
    _cacheActivas = resultado;
    for (final org in resultado) {
      _cachePorId[org.id] = org;
    }
    return resultado;
  }

  /// Organizaciones activas de un rubro puntual (ver TipoOrganizacion),
  /// para la pantalla de "Elegí tu organización" después de que el
  /// usuario ya eligió el rubro en la pantalla anterior. Reusa el
  /// mismo listado/caché de [listarActivas] y filtra en memoria -- no
  /// vale la pena un viaje aparte al servidor por esto.
  Future<List<OrganizacionBranding>> listarActivasPorTipo(
    TipoOrganizacion tipo, {
    bool forzar = false,
  }) async {
    final todas = await listarActivas(forzar: forzar);
    return todas.where((org) => org.tipo == tipo).toList();
  }

  /// La organización de un usuario ya logueado (por su organizacion_id).
  Future<OrganizacionBranding> obtener(String organizacionId) async {
    final cacheada = _cachePorId[organizacionId];
    if (cacheada != null) return cacheada;
    final row = await _client
        .from('organizaciones')
        .select(_columnas)
        .eq('id', organizacionId)
        .single();
    final org = OrganizacionBranding.fromMap(row);
    _cachePorId[organizacionId] = org;
    return org;
  }
}
