import '../../../core/config/supabase_config.dart';
import '../../../shared/models/tipo_organizacion.dart';

/// Un pedido de alta de organización nueva, hecho desde la pantalla
/// pública "Solicitar organización" (antes de loguearse). Ver migración
/// 0050_solicitudes_organizacion.sql.
class SolicitudOrganizacionItem {
  final String id;
  final String nombreOrganizacion;
  final TipoOrganizacion? tipo;
  final String nombrePresidente;
  final DateTime creadoEn;

  SolicitudOrganizacionItem({
    required this.id,
    required this.nombreOrganizacion,
    required this.tipo,
    required this.nombrePresidente,
    required this.creadoEn,
  });

  factory SolicitudOrganizacionItem.fromMap(Map<String, dynamic> map) {
    return SolicitudOrganizacionItem(
      id: map['id'] as String,
      nombreOrganizacion: map['nombre_organizacion'] as String,
      tipo: TipoOrganizacion.desdeValorDb(map['tipo'] as String?),
      nombrePresidente: map['nombre_presidente'] as String,
      creadoEn: DateTime.parse(map['creado_en'] as String),
    );
  }
}

class SolicitudOrganizacionException implements Exception {
  final String message;
  SolicitudOrganizacionException(this.message);
  @override
  String toString() => message;
}

class SolicitudOrganizacionService {
  final _client = SupabaseConfig.client;

  /// Envía el pedido -- no requiere sesión iniciada (RLS pública, ver
  /// migración). Se usa desde la pantalla de "Solicitar organización",
  /// alcanzable antes de loguearse.
  Future<void> enviarSolicitud({
    required String nombreOrganizacion,
    required TipoOrganizacion tipo,
    required String nombrePresidente,
  }) async {
    try {
      await _client.from('solicitudes_organizacion').insert({
        'nombre_organizacion': nombreOrganizacion.trim(),
        'tipo': tipo.valorDb,
        'nombre_presidente': nombrePresidente.trim(),
      });
    } catch (_) {
      throw SolicitudOrganizacionException(
        'No se pudo enviar la solicitud. Revisá tu conexión e intentá de nuevo.',
      );
    }
  }

  /// Solo el dueño de plataforma ve esto (RLS).
  Future<List<SolicitudOrganizacionItem>> listarPendientes() async {
    final rows = await _client
        .from('solicitudes_organizacion')
        .select()
        .eq('estado', 'pendiente')
        .order('creado_en');
    return (rows as List)
        .map((r) => SolicitudOrganizacionItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Crea la organización de cero y devuelve su id. Solo el dueño de
  /// plataforma puede llamar esto (chequeado también en el servidor).
  Future<String> aprobar(String solicitudId) async {
    try {
      final resultado = await _client.rpc(
        'aprobar_solicitud_organizacion',
        params: {'p_solicitud_id': solicitudId},
      );
      return resultado as String;
    } catch (_) {
      throw SolicitudOrganizacionException(
        'No se pudo aprobar la solicitud. Intentá de nuevo.',
      );
    }
  }

  Future<void> rechazar(String solicitudId, {String? motivo}) async {
    try {
      await _client.rpc('rechazar_solicitud_organizacion', params: {
        'p_solicitud_id': solicitudId,
        'p_motivo': motivo,
      });
    } catch (_) {
      throw SolicitudOrganizacionException(
        'No se pudo rechazar la solicitud. Intentá de nuevo.',
      );
    }
  }
}
