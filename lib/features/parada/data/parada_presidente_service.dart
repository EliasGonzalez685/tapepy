import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../asociacion/data/parada_resumen.dart';

/// Datos básicos de la parada que preside un usuario (nombre, ubicación,
/// organización) — lo mínimo para armar el header y saber dónde subir
/// documentos/convenios.
class MiParadaInfo {
  final String id;
  final String organizacionId;
  final String nombre;
  final String? ubicacion;

  MiParadaInfo({
    required this.id,
    required this.organizacionId,
    required this.nombre,
    this.ubicacion,
  });

  factory MiParadaInfo.fromMap(Map<String, dynamic> map) {
    return MiParadaInfo(
      id: map['id'] as String,
      organizacionId: map['organizacion_id'] as String,
      nombre: map['nombre'] as String,
      ubicacion: map['ubicacion'] as String?,
    );
  }
}

class ConvenioItem {
  final String id;
  final String? paradaNombre; // solo se completa en el listado de asociación
  final String empresaNombre;
  final String? descripcion;
  final bool activo;
  final DateTime creadoEn;

  ConvenioItem({
    required this.id,
    required this.empresaNombre,
    required this.activo,
    required this.creadoEn,
    this.paradaNombre,
    this.descripcion,
  });

  factory ConvenioItem.fromMap(Map<String, dynamic> map) {
    final parada = map['paradas'] as Map<String, dynamic>?;
    return ConvenioItem(
      id: map['id'] as String,
      paradaNombre: parada?['nombre'] as String?,
      empresaNombre: map['empresa_nombre'] as String,
      descripcion: map['descripcion'] as String?,
      activo: map['activo'] as bool? ?? true,
      creadoEn: DateTime.parse(map['creado_en'] as String),
    );
  }
}

/// Todo lo que el presidente de parada gestiona que no cubre ya
/// `ParadaDetalleService` (que sigue siendo la fuente de lectura para
/// conductores/cuotas/documentos/incidentes, reutilizada tal cual):
/// resolver cuál es su parada, subir documentos DE LA PARADA (no de
/// conductor — esos los sube cada conductor) y convenios con empresas.
class ParadaPresidenteService {
  final _client = SupabaseConfig.client;
  static const _bucket = 'documentos';

  /// null si todavía no fue asignado como presidente de ninguna parada.
  Future<MiParadaInfo?> cargarMiParada(String usuarioId) async {
    final rows = await _client
        .from('paradas')
        .select('id, organizacion_id, nombre, ubicacion')
        .eq('presidente_id', usuarioId)
        .limit(1);
    final lista = rows as List;
    if (lista.isEmpty) return null;
    return MiParadaInfo.fromMap(lista.first as Map<String, dynamic>);
  }

  /// Conteos (conductores, cuotas atrasadas, docs por vencer) para el
  /// encabezado — misma vista `parada_resumen` que usa el panel de
  /// asociación, filtrada a esta única parada.
  Future<ParadaResumen> cargarResumenParada(String paradaId) async {
    final row = await _client.from('parada_resumen').select().eq('id', paradaId).single();
    return ParadaResumen.fromMap(row);
  }

  /// Sube un documento de la parada (ej. habilitación municipal) al
  /// bucket privado, en una carpeta separada de la de documentos de
  /// conductor: documentos/{organizacionId}/paradas/{paradaId}/...
  Future<void> subirDocumentoParada({
    required String organizacionId,
    required String paradaId,
    required String usuarioId,
    required String tipo,
    required Uint8List bytes,
    required String extension,
    DateTime? fechaVencimiento,
    String? descripcion,
  }) async {
    final nombreArchivo = '${tipo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final path = '$organizacionId/paradas/$paradaId/$nombreArchivo';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: _contentType(extension)),
        );

    await _client.from('documentos_parada').insert({
      'organizacion_id': organizacionId,
      'parada_id': paradaId,
      'subido_por': usuarioId,
      'tipo': tipo,
      'archivo_url': path,
      'nombre_archivo': nombreArchivo,
      'fecha_vencimiento':
          fechaVencimiento != null ? _formatoFecha(fechaVencimiento) : null,
      'estado': _estadoSegunVencimiento(fechaVencimiento),
      'descripcion': descripcion,
    });
  }

  Future<String> obtenerUrlFirmada(String path) async {
    return _client.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  Future<List<ConvenioItem>> cargarConvenios(String paradaId) async {
    final rows = await _client
        .from('convenios_parada')
        .select('id, empresa_nombre, descripcion, activo, creado_en')
        .eq('parada_id', paradaId)
        .order('creado_en', ascending: false);
    return (rows as List)
        .map((r) => ConvenioItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Para el panel de presidente de asociación: convenios de TODAS las
  /// paradas de su organización, con el nombre de la parada incluido.
  /// El dueño de plataforma pasa [organizacionId] para acotar a una
  /// sola organización (por RLS ve todas juntas).
  Future<List<ConvenioItem>> cargarConveniosOrganizacion({String? organizacionId}) async {
    var query = _client
        .from('convenios_parada')
        .select('id, empresa_nombre, descripcion, activo, creado_en, paradas(nombre)');
    if (organizacionId != null) {
      query = query.eq('organizacion_id', organizacionId);
    }
    final rows = await query.order('creado_en', ascending: false);
    return (rows as List)
        .map((r) => ConvenioItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> crearConvenio({
    required String organizacionId,
    required String paradaId,
    required String creadoPor,
    required String empresaNombre,
    String? descripcion,
  }) async {
    await _client.from('convenios_parada').insert({
      'organizacion_id': organizacionId,
      'parada_id': paradaId,
      'creado_por': creadoPor,
      'empresa_nombre': empresaNombre,
      'descripcion': (descripcion == null || descripcion.trim().isEmpty) ? null : descripcion.trim(),
    });
  }

  Future<void> eliminarConvenio(String convenioId) async {
    await _client.from('convenios_parada').delete().eq('id', convenioId);
  }

  String _estadoSegunVencimiento(DateTime? vencimiento) {
    if (vencimiento == null) return 'vigente';
    final hoy = DateTime.now();
    final dias = vencimiento.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
    if (dias < 0) return 'vencido';
    if (dias <= 30) return 'por_vencer';
    return 'vigente';
  }

  String _formatoFecha(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

  String _contentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }
}
