import '../../../core/config/supabase_config.dart';

/// Solicitud de constancia vista por el conductor que la pidió: solo
/// necesita saber en qué estado está y, si ya fue aprobada, con qué
/// tipo de socio quedó redactada (para armar el PDF).
class MiSolicitudConstancia {
  final String id;
  final String estado;
  final String? tipoSocio;
  final DateTime creadoEn;

  MiSolicitudConstancia({
    required this.id,
    required this.estado,
    required this.creadoEn,
    this.tipoSocio,
  });

  factory MiSolicitudConstancia.fromMap(Map<String, dynamic> map) {
    return MiSolicitudConstancia(
      id: map['id'] as String,
      estado: map['estado'] as String,
      tipoSocio: map['tipo_socio'] as String?,
      creadoEn: DateTime.parse(map['creado_en'] as String),
    );
  }
}

/// Solicitud de constancia vista por el presidente de asociación: acá sí
/// hace falta saber quién la pidió y de qué parada, para poder resolver
/// y redactar el documento.
class SolicitudConstanciaItem {
  final String id;
  final String solicitanteId;
  final String solicitanteNombre;
  final String? solicitanteCedula;
  final String paradaId;
  final String paradaNombre;
  final DateTime creadoEn;

  SolicitudConstanciaItem({
    required this.id,
    required this.solicitanteId,
    required this.solicitanteNombre,
    required this.paradaId,
    required this.paradaNombre,
    required this.creadoEn,
    this.solicitanteCedula,
  });

  factory SolicitudConstanciaItem.fromMap(Map<String, dynamic> map) {
    final solicitante = map['solicitante'] as Map<String, dynamic>;
    final parada = map['paradas'] as Map<String, dynamic>?;
    return SolicitudConstanciaItem(
      id: map['id'] as String,
      solicitanteId: solicitante['id'] as String,
      solicitanteNombre: solicitante['nombre'] as String? ?? 'Sin nombre',
      solicitanteCedula: solicitante['cedula'] as String?,
      paradaId: map['parada_id'] as String,
      paradaNombre: parada?['nombre'] as String? ?? 'Sin parada',
      creadoEn: DateTime.parse(map['creado_en'] as String),
    );
  }
}

/// Datos ya resueltos, listos para redactar el PDF de la constancia
/// (nombre, cédula, tipo de socio, parada y organización).
class ConstanciaParaImprimir {
  final String nombre;
  final String? cedula;
  final String tipoSocio;
  final String paradaNombre;
  final String organizacionNombre;
  final DateTime fecha;

  ConstanciaParaImprimir({
    required this.nombre,
    required this.tipoSocio,
    required this.paradaNombre,
    required this.organizacionNombre,
    required this.fecha,
    this.cedula,
  });
}

class ConstanciaService {
  final _client = SupabaseConfig.client;

  /// Crea la solicitud. Si el conductor ya tiene una pendiente no hace
  /// falta duplicarla — eso lo controla la pantalla antes de llamar acá.
  Future<void> solicitarConstancia({
    required String organizacionId,
    required String paradaId,
    required String usuarioId,
  }) async {
    await _client.from('solicitudes_constancia').insert({
      'organizacion_id': organizacionId,
      'parada_id': paradaId,
      'solicitante_id': usuarioId,
    });
  }

  /// La solicitud más reciente del propio conductor (o null si nunca
  /// pidió ninguna) — alcanza con esta para decidir qué mostrarle.
  Future<MiSolicitudConstancia?> cargarMiUltimaSolicitud(String usuarioId) async {
    final row = await _client
        .from('solicitudes_constancia')
        .select('id, estado, tipo_socio, creado_en')
        .eq('solicitante_id', usuarioId)
        .order('creado_en', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : MiSolicitudConstancia.fromMap(row);
  }

  /// Todo lo necesario para armar el PDF de una constancia ya aprobada.
  Future<ConstanciaParaImprimir> cargarParaImprimir(String solicitudId) async {
    final row = await _client
        .from('solicitudes_constancia')
        .select(
            'tipo_socio, creado_en, resuelto_en, paradas(nombre), organizaciones(nombre), usuarios!solicitudes_constancia_solicitante_id_fkey(nombre, cedula)')
        .eq('id', solicitudId)
        .single();
    final usuario = row['usuarios'] as Map<String, dynamic>;
    final parada = row['paradas'] as Map<String, dynamic>?;
    final organizacion = row['organizaciones'] as Map<String, dynamic>?;
    final resueltoEn = row['resuelto_en'] as String?;
    return ConstanciaParaImprimir(
      nombre: usuario['nombre'] as String? ?? 'Sin nombre',
      cedula: usuario['cedula'] as String?,
      tipoSocio: row['tipo_socio'] as String? ?? 'chofer',
      paradaNombre: parada?['nombre'] as String? ?? '',
      organizacionNombre: organizacion?['nombre'] as String? ?? 'TRAUDE',
      fecha: resueltoEn != null ? DateTime.parse(resueltoEn) : DateTime.parse(row['creado_en'] as String),
    );
  }

  /// Pendientes de toda la organización — las resuelve el presidente de
  /// asociación (o el dueño de plataforma supervisando esa org).
  Future<List<SolicitudConstanciaItem>> cargarSolicitudesPendientes({
    required String organizacionId,
  }) async {
    final rows = await _client
        .from('solicitudes_constancia')
        .select(
            'id, parada_id, creado_en, paradas(nombre), solicitante:usuarios!solicitudes_constancia_solicitante_id_fkey(id, nombre, cedula)')
        .eq('organizacion_id', organizacionId)
        .eq('estado', 'pendiente')
        .order('creado_en');
    return (rows as List)
        .map((r) => SolicitudConstanciaItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> resolverSolicitud({
    required String solicitudId,
    required bool aprobar,
    String? tipoSocio,
  }) async {
    await _client.from('solicitudes_constancia').update({
      'estado': aprobar ? 'aprobada' : 'rechazada',
      'tipo_socio': aprobar ? tipoSocio : null,
      'resuelto_en': DateTime.now().toIso8601String(),
    }).eq('id', solicitudId);
  }
}
