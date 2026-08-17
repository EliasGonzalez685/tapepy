import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import 'parada_resumen.dart';

class ParadaException implements Exception {
  final String message;
  ParadaException(this.message);
  @override
  String toString() => message;
}

class AsociacionDashboardTotales {
  final int paradasActivas;
  final int miembros;
  final int cuotasAtrasadas;
  final int docsPorVencer;
  // Total de conductores con "en servicio" prendido ahora mismo, sumado
  // entre todas las paradas — para el banner de pulso en vivo del panel.
  final int conductoresActivos;
  final List<ParadaResumen> paradas;

  AsociacionDashboardTotales({
    required this.paradasActivas,
    required this.miembros,
    required this.cuotasAtrasadas,
    required this.docsPorVencer,
    required this.conductoresActivos,
    required this.paradas,
  });
}

/// Datos para el panel del presidente de asociación. RLS ya filtra todo
/// por la organización del usuario logueado, no hace falta pasar el
/// organizacion_id a mano en las queries — EXCEPTO para el dueño de
/// plataforma, que por RLS puede ver todas las organizaciones a la vez
/// y necesita el filtro explícito para pararse en una sola.
class AsociacionDashboardService {
  final _client = SupabaseConfig.client;

  Future<AsociacionDashboardTotales> cargarResumen({String? organizacionId}) async {
    var query = _client.from('parada_resumen').select();
    if (organizacionId != null) {
      query = query.eq('organizacion_id', organizacionId);
    }
    final rows = await query.order('nombre');

    // La vista `parada_resumen` no trae el estado "en servicio" (es un
    // dato en vivo, no algo que valga la pena materializar en la vista),
    // así que se calcula acá aparte: conductores de la organización con
    // su bandera, agrupados por parada.
    var activosQuery = _client.from('conductores').select('parada_id, usuarios!inner(en_servicio)');
    if (organizacionId != null) {
      activosQuery = activosQuery.eq('organizacion_id', organizacionId);
    }
    final activosRows = await activosQuery;

    final conteoActivos = <String, int>{};
    for (final row in activosRows as List) {
      final map = row as Map<String, dynamic>;
      final usuario = map['usuarios'] as Map<String, dynamic>?;
      if (usuario?['en_servicio'] != true) continue;
      final paradaId = map['parada_id'] as String?;
      if (paradaId == null) continue;
      conteoActivos[paradaId] = (conteoActivos[paradaId] ?? 0) + 1;
    }

    final paradas = (rows as List).map((row) {
      final resumen = ParadaResumen.fromMap(row as Map<String, dynamic>);
      return resumen.copyWith(conductoresActivosCount: conteoActivos[resumen.id] ?? 0);
    }).toList();

    final miembros = paradas.fold<int>(0, (sum, p) => sum + p.conductoresCount);
    final cuotasAtrasadas =
        paradas.fold<int>(0, (sum, p) => sum + p.cuotasAtrasadasCount);
    final docsPorVencer =
        paradas.fold<int>(0, (sum, p) => sum + p.docsPorVencerCount);
    final conductoresActivos =
        paradas.fold<int>(0, (sum, p) => sum + p.conductoresActivosCount);

    return AsociacionDashboardTotales(
      paradasActivas: paradas.length,
      miembros: miembros,
      cuotasAtrasadas: cuotasAtrasadas,
      docsPorVencer: docsPorVencer,
      conductoresActivos: conductoresActivos,
      paradas: paradas,
    );
  }

  /// Alta de una parada nueva. Solo el presidente de asociación puede
  /// hacerlo (reforzado por RLS, ver migración
  /// 0012_paradas_alta_presidente.sql) — hace falta que exista al
  /// menos una parada para que aparezca como opción en el registro de
  /// conductores.
  Future<void> crearParada({
    required String organizacionId,
    required String nombre,
    String? ubicacion,
    String? resolucionNumero,
  }) async {
    await _client.from('paradas').insert({
      'organizacion_id': organizacionId,
      'nombre': nombre,
      'ubicacion': (ubicacion == null || ubicacion.trim().isEmpty) ? null : ubicacion.trim(),
      'resolucion_numero':
          (resolucionNumero == null || resolucionNumero.trim().isEmpty) ? null : resolucionNumero.trim(),
    });
  }

  /// La resolución de la parada puede cargarse después de crearla, o
  /// corregirse más adelante — no hace falta tenerla desde el alta.
  Future<void> actualizarResolucionParada({
    required String paradaId,
    String? resolucionNumero,
  }) async {
    await _client.from('paradas').update({
      'resolucion_numero':
          (resolucionNumero == null || resolucionNumero.trim().isEmpty) ? null : resolucionNumero.trim(),
    }).eq('id', paradaId);
  }

  /// Listado de paradas con su cantidad de conductores, para la
  /// pantalla de gestión (crear/eliminar) desde el drawer.
  Future<List<ParadaResumen>> cargarParadas({String? organizacionId}) async {
    var query = _client.from('parada_resumen').select();
    if (organizacionId != null) {
      query = query.eq('organizacion_id', organizacionId);
    }
    final rows = await query.order('nombre');
    return (rows as List)
        .map((row) => ParadaResumen.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Elimina una parada. Si tiene conductores, cuotas u otros datos que
  /// la referencian, la base la rechaza (FK `on delete restrict`) —
  /// se traduce acá a un mensaje entendible en vez de dejar pasar el
  /// error crudo de Postgres.
  Future<void> eliminarParada(String paradaId) async {
    try {
      await _client.from('paradas').delete().eq('id', paradaId);
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw ParadaException(
          'No se puede eliminar: todavía tiene conductores, pagos u otros datos asociados.',
        );
      }
      throw ParadaException('No se pudo eliminar la parada. Intentá de nuevo.');
    }
  }
}
