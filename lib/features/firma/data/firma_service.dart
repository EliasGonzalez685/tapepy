import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

/// Estado de la firma de "el otro presidente" respecto de quien está
/// armando el listado: si no la pidió todavía, si ya la pidió y está
/// esperando, o si ya se la aprobaron (o rechazaron) — igual mecanismo
/// que la aprobación de cuenta de un conductor: una vez aprobada, queda
/// válida para los próximos listados también, no hay que volver a
/// pedirla.
enum EstadoFirma { ninguna, pendiente, aprobada, rechazada }

class SolicitudFirmaItem {
  final String id;
  final String paradaId;
  final String? paradaNombre;
  final String solicitanteId;
  final String solicitanteNombre;
  final String solicitanteRolLabel;
  final DateTime creadoEn;

  SolicitudFirmaItem({
    required this.id,
    required this.paradaId,
    required this.solicitanteId,
    required this.solicitanteNombre,
    required this.solicitanteRolLabel,
    required this.creadoEn,
    this.paradaNombre,
  });

  factory SolicitudFirmaItem.fromMap(Map<String, dynamic> map) {
    final solicitante = map['solicitante'] as Map<String, dynamic>;
    final parada = map['paradas'] as Map<String, dynamic>?;
    return SolicitudFirmaItem(
      id: map['id'] as String,
      paradaId: map['parada_id'] as String,
      paradaNombre: parada?['nombre'] as String?,
      solicitanteId: solicitante['id'] as String,
      solicitanteNombre: solicitante['nombre'] as String,
      solicitanteRolLabel:
          solicitante['rol'] == 'presidente_asociacion' ? 'Presidente de Asociación' : 'Presidente de Parada',
      creadoEn: DateTime.parse(map['creado_en'] as String),
    );
  }
}

/// Firma digital de cada presidente + las solicitudes para poder usar la
/// firma de OTRO presidente en un listado impreso. El mecanismo es
/// simétrico: tanto el presidente de asociación como el de parada
/// pueden necesitar la firma del otro, y en los dos casos hace falta
/// pedirla y que el dueño de esa firma la apruebe (ver migración
/// firmas_digitales.sql).
class FirmaService {
  final _client = SupabaseConfig.client;
  static const _bucket = 'firmas';

  Future<String?> cargarFirmaUrl(String usuarioId) async {
    final row = await _client.from('usuarios').select('firma_url').eq('id', usuarioId).maybeSingle();
    return row?['firma_url'] as String?;
  }

  /// Sube la imagen de firma a `firmas/{organizacionId}/{usuarioId}/firma.png`
  /// (bucket privado, se reemplaza en cada subida) y guarda la RUTA (no
  /// una URL) en `usuarios.firma_url` — para mostrarla o embeberla en un
  /// PDF hace falta pedir una URL firmada con [obtenerUrlFirmada].
  Future<String> subirFirma({
    required String usuarioId,
    required String organizacionId,
    required Uint8List bytes,
  }) async {
    final path = '$organizacionId/$usuarioId/firma.png';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/png'),
        );
    await _client.from('usuarios').update({'firma_url': path}).eq('id', usuarioId);
    return path;
  }

  Future<String> obtenerUrlFirmada(String path) {
    return _client.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  /// Id del presidente de asociación de la organización (si ya hay uno
  /// con cuenta creada).
  Future<String?> obtenerPresidenteAsociacionId(String organizacionId) async {
    final row = await _client
        .from('usuarios')
        .select('id')
        .eq('organizacion_id', organizacionId)
        .eq('rol', 'presidente_asociacion')
        .maybeSingle();
    return row?['id'] as String?;
  }

  /// Id del presidente de una parada puntual (si ya tiene uno asignado).
  Future<String?> obtenerPresidenteParadaId(String paradaId) async {
    final row = await _client.from('paradas').select('presidente_id').eq('id', paradaId).single();
    return row['presidente_id'] as String?;
  }

  Future<EstadoFirma> consultarEstado({
    required String solicitanteId,
    required String firmanteId,
    required String paradaId,
  }) async {
    final row = await _client
        .from('solicitudes_firma')
        .select('estado')
        .eq('solicitante_id', solicitanteId)
        .eq('firmante_id', firmanteId)
        .eq('parada_id', paradaId)
        .maybeSingle();
    if (row == null) return EstadoFirma.ninguna;
    switch (row['estado'] as String) {
      case 'aprobada':
        return EstadoFirma.aprobada;
      case 'rechazada':
        return EstadoFirma.rechazada;
      default:
        return EstadoFirma.pendiente;
    }
  }

  /// Crea la solicitud, o la reactiva (vuelve a 'pendiente') si ya
  /// existía una rechazada de antes para ese mismo par + parada.
  Future<void> solicitarFirma({
    required String organizacionId,
    required String paradaId,
    required String solicitanteId,
    required String firmanteId,
  }) async {
    await _client.from('solicitudes_firma').upsert(
      {
        'organizacion_id': organizacionId,
        'parada_id': paradaId,
        'solicitante_id': solicitanteId,
        'firmante_id': firmanteId,
        'estado': 'pendiente',
        'creado_en': DateTime.now().toIso8601String(),
        'resuelto_en': null,
      },
      onConflict: 'solicitante_id,firmante_id,parada_id',
    );
  }

  Future<List<SolicitudFirmaItem>> cargarSolicitudesPendientes(String firmanteId) async {
    final rows = await _client
        .from('solicitudes_firma')
        .select('id, parada_id, creado_en, paradas(nombre), solicitante:usuarios!solicitudes_firma_solicitante_id_fkey(id, nombre, rol)')
        .eq('firmante_id', firmanteId)
        .eq('estado', 'pendiente')
        .order('creado_en');
    return (rows as List)
        .map((r) => SolicitudFirmaItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> resolverSolicitud({
    required String solicitudId,
    required bool aprobar,
  }) async {
    await _client.from('solicitudes_firma').update({
      'estado': aprobar ? 'aprobada' : 'rechazada',
      'resuelto_en': DateTime.now().toIso8601String(),
    }).eq('id', solicitudId);
  }
}
