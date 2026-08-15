import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

/// Pagos grupales ("a todos") — ver migración 0025_lotes_pago.sql. Un
/// lote guarda los datos compartidos del pago (motivo, monto, mes/año,
/// fechas) y, al crearse, genera una fila individual en
/// cuotas_mensuales para cada conductor del alcance elegido (una
/// parada, o todas las de la organización si lo hace el presidente de
/// asociación). Cada quien sigue marcando su propia fila como pagada,
/// subiendo comprobante, etc. — el lote solo agrupa y permite ver
/// "cuántos de este pago ya pagaron".
class LotePagoException implements Exception {
  final String message;
  LotePagoException(this.message);
  @override
  String toString() => message;
}

class LotePago {
  final String id;
  final String organizacionId;
  final List<String>? paradaIds; // null/vacío = todas las paradas de la organización
  final String motivo;
  final double montoBase;
  final double montoAdicional;
  final double montoTotal;
  final int mes;
  final int anio;
  final DateTime fechaVencimiento;
  final DateTime fechaLimite;
  final String? creadoPor;
  final DateTime creadoEn;

  LotePago({
    required this.id,
    required this.organizacionId,
    this.paradaIds,
    required this.motivo,
    required this.montoBase,
    required this.montoAdicional,
    required this.montoTotal,
    required this.mes,
    required this.anio,
    required this.fechaVencimiento,
    required this.fechaLimite,
    this.creadoPor,
    required this.creadoEn,
  });

  factory LotePago.fromMap(Map<String, dynamic> map) {
    return LotePago(
      id: map['id'] as String,
      organizacionId: map['organizacion_id'] as String,
      paradaIds: (map['parada_ids'] as List?)?.map((e) => e as String).toList(),
      motivo: map['motivo'] as String,
      montoBase: (map['monto_base'] as num).toDouble(),
      montoAdicional: (map['monto_adicional'] as num).toDouble(),
      montoTotal: (map['monto_total'] as num).toDouble(),
      mes: (map['mes'] as num).toInt(),
      anio: (map['anio'] as num).toInt(),
      fechaVencimiento: DateTime.parse(map['fecha_vencimiento'] as String),
      fechaLimite: DateTime.parse(map['fecha_limite'] as String),
      creadoPor: map['creado_por'] as String?,
      creadoEn: DateTime.parse(map['creado_en'] as String),
    );
  }
}

class LotePagoService {
  final _client = SupabaseConfig.client;

  /// Crea el lote y genera en batch una cuota por cada conductor del
  /// alcance elegido:
  /// - [paradaIds] no nulo/no vacío: exactamente esas paradas (puede
  ///   ser una sola — presidente de parada siempre manda su propia
  ///   parada así — o un subconjunto elegido a mano por el presidente
  ///   de asociación, ej. 5 de 10).
  /// - [paradaIds] nulo o vacío: todas las paradas de la organización
  ///   (solo presidente de asociación — la RLS de lotes_pago ya lo
  ///   exige).
  ///
  /// Cada cuota generada usa la parada real del conductor (no
  /// necesariamente algo de [paradaIds], que puede ser null en el caso
  /// "todas"), porque cuotas_mensuales.parada_id es NOT NULL.
  ///
  /// [usuarioIds], si viene con valores, acota todavía más: genera la
  /// cuota solo para esos conductores puntuales (ej. el presidente de
  /// parada excluyendo a algunos socios de su propia parada), sin
  /// importar [paradaIds] para esta consulta — [paradaIds] igual se
  /// guarda en la fila de lotes_pago como el alcance "de origen".
  Future<void> crearLotePago({
    required String organizacionId,
    List<String>? paradaIds,
    List<String>? usuarioIds,
    required String motivo,
    required double montoBase,
    double montoAdicional = 0,
    required int mes,
    required int anio,
    required DateTime fechaVencimiento,
    required DateTime fechaLimite,
    required String creadoPor,
  }) async {
    final alcance = (paradaIds == null || paradaIds.isEmpty) ? null : paradaIds;
    final soloEstos = (usuarioIds == null || usuarioIds.isEmpty) ? null : usuarioIds;
    final montoTotal = montoBase + montoAdicional;
    try {
      final lote = await _client
          .from('lotes_pago')
          .insert({
            'organizacion_id': organizacionId,
            'parada_ids': alcance,
            'motivo': motivo,
            'monto_base': montoBase,
            'monto_adicional': montoAdicional,
            'monto_total': montoTotal,
            'mes': mes,
            'anio': anio,
            'fecha_vencimiento': _formatoFecha(fechaVencimiento),
            'fecha_limite': _formatoFecha(fechaLimite),
            'creado_por': creadoPor,
          })
          .select('id')
          .single();
      final loteId = lote['id'] as String;

      var query = _client.from('conductores').select('usuario_id, parada_id').eq(
            'organizacion_id',
            organizacionId,
          );
      if (soloEstos != null) {
        query = query.inFilter('usuario_id', soloEstos);
      } else if (alcance != null) {
        query = query.inFilter('parada_id', alcance);
      }
      final conductores = await query;

      if ((conductores as List).isEmpty) {
        throw LotePagoException('No hay socios en el alcance elegido para generar el pago.');
      }

      final filas = conductores.map((c) {
        final map = c as Map<String, dynamic>;
        return {
          'organizacion_id': organizacionId,
          'usuario_id': map['usuario_id'],
          'parada_id': map['parada_id'],
          'lote_id': loteId,
          'motivo': motivo,
          'mes': mes,
          'anio': anio,
          'monto_base': montoBase,
          'monto_adicional': montoAdicional,
          'monto_total': montoTotal,
          'fecha_vencimiento': _formatoFecha(fechaVencimiento),
          'fecha_limite': _formatoFecha(fechaLimite),
          'registrado_por': creadoPor,
        };
      }).toList();

      await _client.from('cuotas_mensuales').insert(filas);
    } on LotePagoException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw LotePagoException(
            'Algunos socios ya tienen un pago con ese motivo cargado para ese mes.');
      }
      throw LotePagoException('No se pudo generar el pago grupal. Intentá de nuevo.');
    } catch (_) {
      throw LotePagoException('No se pudo generar el pago grupal. Intentá de nuevo.');
    }
  }

  /// Lotes generados que incluyen una parada puntual (parada_ids la
  /// contiene, o parada_ids es null = todas), o todos los de la
  /// organización si no se pasa [paradaId] — para listar los pagos
  /// grupales activos y su alcance.
  Future<List<LotePago>> cargarLotes({
    String? paradaId,
    String? organizacionId,
  }) async {
    var query = _client.from('lotes_pago').select();
    if (paradaId != null) {
      query = query.or('parada_ids.is.null,parada_ids.cs.{$paradaId}');
    } else if (organizacionId != null) {
      query = query.eq('organizacion_id', organizacionId);
    }
    final rows = await query.order('creado_en', ascending: false);
    return (rows as List).map((r) => LotePago.fromMap(r as Map<String, dynamic>)).toList();
  }

  String _formatoFecha(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
}
