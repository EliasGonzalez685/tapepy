import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

/// Cuota de plataforma: lo que cada persona (presidente de asociación,
/// presidente de parada, conductor) le paga al DUEÑO de la plataforma
/// por el servicio de TapePy en sí -- totalmente distinta de
/// cuotas_mensuales (esa es la cuota interna que el conductor paga a su
/// parada/asociación, ver ConductorService/LotePagoService).
///
/// Modelo autoservicio puro (pedido de Elias 2026-08-21): no hay
/// "cargo del mes" pre-generado por el dueño -- cada persona reporta
/// su propio pago cuando paga y listo. El monto es fijo por
/// organización pero editable por el dueño (organizaciones.
/// cuota_plataforma_monto). Días 1 al 15 de cada mes son de gracia
/// (pendiente); desde el 16, si no hay pago del mes, la persona
/// aparece como morosa automáticamente -- no se guarda nada para eso,
/// se calcula al vuelo (ver usuario_en_deuda_plataforma en la base y
/// EstadoCuotaPlataformaOrg acá). Si alguien queda en deuda su
/// carnet/QR deja de funcionar (ver Edge Function verificar-carnet).
class CuotaPlataformaException implements Exception {
  final String message;
  CuotaPlataformaException(this.message);
  @override
  String toString() => message;
}

/// Una fila histórica de cuotas_plataforma (un pago ya reportado).
class CuotaPlataformaItem {
  final String id;
  final String usuarioId;
  final String organizacionId;
  final int mes;
  final int anio;
  final double monto;
  final String estado; // pendiente | pagado | atrasado | exonerado
  final DateTime? fechaPago;
  final String? metodoPago;
  final String? comprobanteUrl;
  final String motivo;

  CuotaPlataformaItem({
    required this.id,
    required this.usuarioId,
    required this.organizacionId,
    required this.mes,
    required this.anio,
    required this.monto,
    required this.estado,
    required this.motivo,
    this.fechaPago,
    this.metodoPago,
    this.comprobanteUrl,
  });

  bool get alDia => estado == 'pagado' || estado == 'exonerado';

  factory CuotaPlataformaItem.fromMap(Map<String, dynamic> map) {
    return CuotaPlataformaItem(
      id: map['id'] as String,
      usuarioId: map['usuario_id'] as String,
      organizacionId: map['organizacion_id'] as String,
      mes: (map['mes'] as num).toInt(),
      anio: (map['anio'] as num).toInt(),
      monto: (map['monto'] as num).toDouble(),
      estado: map['estado'] as String,
      motivo: map['motivo'] as String? ?? 'Cuota de plataforma',
      fechaPago: map['fecha_pago'] != null ? DateTime.parse(map['fecha_pago'] as String) : null,
      metodoPago: map['metodo_pago'] as String?,
      comprobanteUrl: map['comprobante_url'] as String?,
    );
  }
}

/// Estado actual (mes en curso) de la cuota de plataforma de una
/// persona -- ya sea la propia (ver [CuotaPlataformaService.cargarMiEstado])
/// o la de otra dentro de una organización (ver
/// [CuotaPlataformaService.cargarEstadoOrganizacion]). "moroso" nunca
/// se guarda: es el resultado de no tener pago del mes actual después
/// del día 15.
class EstadoCuotaPlataforma {
  final String usuarioId;
  final String? nombre;
  final String? rol;
  final String? paradaId;
  final String? paradaNombre;
  final String estado; // pendiente | pagado | exonerado | moroso
  final double monto;
  final DateTime? fechaPago;
  final String? metodoPago;
  final String? comprobanteUrl;
  final String? cuotaId;

  EstadoCuotaPlataforma({
    required this.usuarioId,
    required this.estado,
    required this.monto,
    this.nombre,
    this.rol,
    this.paradaId,
    this.paradaNombre,
    this.fechaPago,
    this.metodoPago,
    this.comprobanteUrl,
    this.cuotaId,
  });

  bool get enDeuda => estado == 'moroso';
  bool get alDia => estado == 'pagado' || estado == 'exonerado';

  factory EstadoCuotaPlataforma.fromMap(Map<String, dynamic> map) {
    return EstadoCuotaPlataforma(
      usuarioId: map['usuario_id'] as String,
      nombre: map['nombre'] as String?,
      rol: map['rol'] as String?,
      paradaId: map['parada_id'] as String?,
      paradaNombre: map['parada_nombre'] as String?,
      estado: map['estado'] as String,
      monto: (map['monto'] as num).toDouble(),
      fechaPago: map['fecha_pago'] != null ? DateTime.parse(map['fecha_pago'] as String) : null,
      metodoPago: map['metodo_pago'] as String?,
      comprobanteUrl: map['comprobante_url'] as String?,
      cuotaId: map['cuota_id'] as String?,
    );
  }
}

/// Agrupa [EstadoCuotaPlataforma] de una organización por parada -- los
/// que no mapean a ninguna (ej. el propio presidente de asociación si
/// no preside ninguna parada) quedan bajo [paradaNombre] null,
/// agrupados como "Sin parada".
class GrupoEstadoCuotaPlataforma {
  final String? paradaId;
  final String? paradaNombre;
  final List<EstadoCuotaPlataforma> estados;

  GrupoEstadoCuotaPlataforma({required this.paradaId, required this.paradaNombre, required this.estados});

  int get total => estados.length;
  int get enDeuda => estados.where((e) => e.enDeuda).length;
  int get alDia => estados.where((e) => e.alDia).length;
}

class CuotaPlataformaService {
  final _client = SupabaseConfig.client;
  static const _bucket = 'comprobantes';

  /// Historial completo de pagos ya reportados por un usuario (más
  /// reciente primero).
  Future<List<CuotaPlataformaItem>> cargarMia(String usuarioId) async {
    final rows = await _client
        .from('cuotas_plataforma')
        .select('id, usuario_id, organizacion_id, mes, anio, monto, estado, fecha_pago, comprobante_url, metodo_pago, motivo')
        .eq('usuario_id', usuarioId)
        .order('anio', ascending: false)
        .order('mes', ascending: false);
    return (rows as List).map((r) => CuotaPlataformaItem.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Estado actual (mes en curso) de la cuota propia -- combina el
  /// monto configurado por el dueño para la organización con el
  /// historial, sin depender de ninguna fila pre-generada.
  Future<EstadoCuotaPlataforma> cargarMiEstado({
    required String usuarioId,
    required String organizacionId,
  }) async {
    final hoy = DateTime.now();
    final orgFuture =
        _client.from('organizaciones').select('cuota_plataforma_monto').eq('id', organizacionId).single();
    final historialFuture = cargarMia(usuarioId);
    final resultados = await Future.wait([orgFuture, historialFuture]);
    final org = resultados[0] as Map<String, dynamic>;
    final historial = resultados[1] as List<CuotaPlataformaItem>;
    final montoConfigurado = (org['cuota_plataforma_monto'] as num?)?.toDouble() ?? 50000;

    CuotaPlataformaItem? actual;
    for (final c in historial) {
      if (c.mes == hoy.month && c.anio == hoy.year) {
        actual = c;
        break;
      }
    }

    if (actual != null) {
      return EstadoCuotaPlataforma(
        usuarioId: usuarioId,
        estado: actual.estado,
        monto: actual.monto,
        fechaPago: actual.fechaPago,
        metodoPago: actual.metodoPago,
        comprobanteUrl: actual.comprobanteUrl,
        cuotaId: actual.id,
      );
    }

    final moroso = hoy.day > 15;
    return EstadoCuotaPlataforma(
      usuarioId: usuarioId,
      estado: moroso ? 'moroso' : 'pendiente',
      monto: montoConfigurado,
    );
  }

  /// El usuario reporta que ya pagó su cuota de plataforma del mes en
  /// curso -- INSERT directo (ya no hay fila pre-generada que
  /// actualizar). El trigger de la base (cuotas_plataforma_
  /// set_organizacion) fuerza usuario_id/mes/año/estado/monto del lado
  /// del servidor, así que lo único que manda el cliente es cómo y
  /// cuándo pagó. Usa el mismo bucket "comprobantes" que cuotas_
  /// mensuales, con prefijo "plataforma_" para no mezclarse.
  Future<void> reportarPago({
    required String usuarioId,
    required String organizacionId,
    required String metodoPago, // 'efectivo' | 'transferencia'
    required DateTime fechaPago,
    Uint8List? bytes,
    String? extension,
  }) async {
    if (metodoPago == 'transferencia' && (bytes == null || extension == null)) {
      throw CuotaPlataformaException('Adjuntá el comprobante de la transferencia.');
    }
    try {
      String? path;
      if (metodoPago == 'transferencia') {
        final sello = DateTime.now().millisecondsSinceEpoch;
        path = '$organizacionId/$usuarioId/plataforma_$sello.$extension';
        await _client.storage.from(_bucket).uploadBinary(
              path,
              bytes!,
              fileOptions: FileOptions(upsert: true, contentType: _contentType(extension!)),
            );
      }
      await _client.from('cuotas_plataforma').insert({
        'usuario_id': usuarioId,
        if (path != null) 'comprobante_url': path,
        'metodo_pago': metodoPago,
        'fecha_pago': _formatoFecha(fechaPago),
      });
    } on CuotaPlataformaException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw CuotaPlataformaException('Ya reportaste tu pago de este mes.');
      }
      throw CuotaPlataformaException('No se pudo registrar el pago. Intentá de nuevo.');
    } catch (_) {
      throw CuotaPlataformaException('No se pudo registrar el pago. Intentá de nuevo.');
    }
  }

  Future<String> obtenerUrlComprobante(String path) {
    return _client.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  /// Override manual del dueño de plataforma: registra un pago (ej.
  /// cobrado en efectivo en persona) o una exoneración a nombre de
  /// otra persona para el mes actual. Al ser el dueño quien inserta,
  /// el trigger de autoservicio no lo pisa.
  Future<void> registrarManual({
    required String usuarioId,
    required String estado, // pagado | exonerado
    required String registradoPor,
  }) async {
    final hoy = DateTime.now();
    try {
      await _client.from('cuotas_plataforma').insert({
        'usuario_id': usuarioId,
        'mes': hoy.month,
        'anio': hoy.year,
        'estado': estado,
        'registrado_por': registradoPor,
        'fecha_pago': _formatoFecha(hoy),
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw CuotaPlataformaException('Ya existe un registro de este mes para esa persona.');
      }
      throw CuotaPlataformaException('No se pudo registrar. Intentá de nuevo.');
    } catch (_) {
      throw CuotaPlataformaException('No se pudo registrar. Intentá de nuevo.');
    }
  }

  /// Override manual del dueño sobre una fila ya existente (revertir a
  /// pendiente/atrasado, o corregir un estado).
  Future<void> marcarEstado({required String cuotaId, required String estado}) async {
    await _client.from('cuotas_plataforma').update({'estado': estado}).eq('id', cuotaId);
  }

  /// Monto configurado actualmente para una organización -- para
  /// prellenar el formulario de edición del dueño.
  Future<double> obtenerMonto(String organizacionId) async {
    final row = await _client
        .from('organizaciones')
        .select('cuota_plataforma_monto')
        .eq('id', organizacionId)
        .single();
    return ((row as Map<String, dynamic>)['cuota_plataforma_monto'] as num?)?.toDouble() ?? 50000;
  }

  /// El dueño de plataforma edita el monto fijo mensual de una
  /// organización -- reemplaza el viejo "Generar cobro del mes".
  Future<void> editarMonto({required String organizacionId, required double monto}) async {
    await _client.from('organizaciones').update({'cuota_plataforma_monto': monto}).eq('id', organizacionId);
  }

  /// Estado del mes en curso de TODOS los miembros pagadores de una
  /// organización (presidente de asociación, presidentes de parada,
  /// conductores), incluidos los que todavía no tienen ninguna fila --
  /// el LEFT JOIN y el cálculo de moroso se hacen en la base (RPC
  /// estado_cuota_plataforma_organizacion) para no tener que replicar
  /// esa lógica acá. Solo dueño de plataforma o presidente de
  /// asociación de esa organización (chequeado también del lado de la
  /// base).
  Future<List<EstadoCuotaPlataforma>> cargarEstadoOrganizacion(String organizacionId) async {
    final rows =
        await _client.rpc('estado_cuota_plataforma_organizacion', params: {'p_organizacion_id': organizacionId});
    return (rows as List).map((r) => EstadoCuotaPlataforma.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Agrupa una lista ya cargada (ver [cargarEstadoOrganizacion]) por
  /// parada -- helper compartido entre la vista del dueño y la de
  /// balance de pagos.
  List<GrupoEstadoCuotaPlataforma> agruparPorParada(List<EstadoCuotaPlataforma> estados) {
    final grupos = <String, List<EstadoCuotaPlataforma>>{};
    final nombres = <String, String?>{};
    for (final e in estados) {
      final clave = e.paradaId ?? '__sin_parada__';
      nombres[clave] = e.paradaNombre;
      grupos.putIfAbsent(clave, () => []).add(e);
    }
    final lista = grupos.entries
        .map((entry) => GrupoEstadoCuotaPlataforma(
              paradaId: entry.key == '__sin_parada__' ? null : entry.key,
              paradaNombre: nombres[entry.key],
              estados: entry.value,
            ))
        .toList();
    lista.sort((a, b) {
      if (a.paradaNombre == null) return 1;
      if (b.paradaNombre == null) return -1;
      return a.paradaNombre!.compareTo(b.paradaNombre!);
    });
    return lista;
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
