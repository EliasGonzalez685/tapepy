import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

/// Cuota de plataforma: lo que cada persona (presidente de asociación,
/// presidente de parada, conductor) le paga al DUEÑO de la plataforma
/// por el servicio de TapePy en sí -- totalmente distinta de
/// cuotas_mensuales (esa es la cuota interna que el conductor paga a su
/// parada/asociación, ver ConductorService/LotePagoService). Pedido de
/// Elias 2026-08-21: cada persona paga individual, solo el dueño
/// gestiona/cobra, el presidente de asociación solo ve el estado de su
/// organización, y si alguien queda en deuda su carnet/QR deja de
/// funcionar (ver Edge Function verificar-carnet).
class CuotaPlataformaException implements Exception {
  final String message;
  CuotaPlataformaException(this.message);
  @override
  String toString() => message;
}

class CuotaPlataformaItem {
  final String id;
  final String usuarioId;
  final String organizacionId;
  final int mes;
  final int anio;
  final double monto;
  final String estado; // pendiente | pagado | atrasado | exonerado
  final DateTime? fechaVencimiento;
  final DateTime? fechaPago;
  final String? metodoPago;
  final String? comprobanteUrl;
  final String motivo;
  // Solo vienen cargados en las vistas de administración (dueño de
  // plataforma / presidente de asociación) -- en "Mi cuota" no hacen
  // falta, ahí ya se sabe de quién es.
  final String? usuarioNombre;
  final String? usuarioRol;
  final String? paradaId;
  final String? paradaNombre;

  CuotaPlataformaItem({
    required this.id,
    required this.usuarioId,
    required this.organizacionId,
    required this.mes,
    required this.anio,
    required this.monto,
    required this.estado,
    required this.motivo,
    this.fechaVencimiento,
    this.fechaPago,
    this.metodoPago,
    this.comprobanteUrl,
    this.usuarioNombre,
    this.usuarioRol,
    this.paradaId,
    this.paradaNombre,
  });

  /// Misma lógica que usuario_en_deuda_plataforma en la base: atrasado,
  /// o pendiente con el vencimiento ya pasado (acá no hay cron que
  /// mueva pendiente->atrasado solo).
  bool get enDeuda {
    if (estado == 'atrasado') return true;
    if (estado == 'pendiente' && fechaVencimiento != null) {
      final hoy = DateTime.now();
      return fechaVencimiento!.isBefore(DateTime(hoy.year, hoy.month, hoy.day));
    }
    return false;
  }

  bool get alDia => estado == 'pagado' || estado == 'exonerado';

  factory CuotaPlataformaItem.fromMap(Map<String, dynamic> map) {
    final usuario = map['usuarios'] as Map<String, dynamic>?;
    return CuotaPlataformaItem(
      id: map['id'] as String,
      usuarioId: map['usuario_id'] as String,
      organizacionId: map['organizacion_id'] as String,
      mes: (map['mes'] as num).toInt(),
      anio: (map['anio'] as num).toInt(),
      monto: (map['monto'] as num).toDouble(),
      estado: map['estado'] as String,
      motivo: map['motivo'] as String? ?? 'Cuota de plataforma',
      fechaVencimiento: map['fecha_vencimiento'] != null
          ? DateTime.parse(map['fecha_vencimiento'] as String)
          : null,
      fechaPago: map['fecha_pago'] != null ? DateTime.parse(map['fecha_pago'] as String) : null,
      metodoPago: map['metodo_pago'] as String?,
      comprobanteUrl: map['comprobante_url'] as String?,
      usuarioNombre: usuario?['nombre'] as String?,
      usuarioRol: usuario?['rol'] as String?,
    );
  }

  CuotaPlataformaItem copyWithParada({String? paradaId, String? paradaNombre}) {
    return CuotaPlataformaItem(
      id: id,
      usuarioId: usuarioId,
      organizacionId: organizacionId,
      mes: mes,
      anio: anio,
      monto: monto,
      estado: estado,
      motivo: motivo,
      fechaVencimiento: fechaVencimiento,
      fechaPago: fechaPago,
      metodoPago: metodoPago,
      comprobanteUrl: comprobanteUrl,
      usuarioNombre: usuarioNombre,
      usuarioRol: usuarioRol,
      paradaId: paradaId ?? this.paradaId,
      paradaNombre: paradaNombre ?? this.paradaNombre,
    );
  }
}

/// Agrupa las cuotas de una organización por parada (el conjunto de
/// conductores de esa parada + su presidente si preside una) -- para la
/// vista de solo lectura del presidente de asociación y para el panel
/// del dueño de plataforma. Los que no mapean a ninguna parada (ej. el
/// propio presidente de asociación si no preside ninguna) quedan bajo
/// [paradaNombre] null, agrupados como "Sin parada".
class GrupoCuotasPorParada {
  final String? paradaId;
  final String? paradaNombre;
  final List<CuotaPlataformaItem> cuotas;

  GrupoCuotasPorParada({required this.paradaId, required this.paradaNombre, required this.cuotas});

  int get total => cuotas.length;
  int get enDeuda => cuotas.where((c) => c.enDeuda).length;
  int get alDia => cuotas.where((c) => c.alDia).length;
}

class CuotaPlataformaService {
  final _client = SupabaseConfig.client;
  static const _bucket = 'comprobantes';

  Future<List<CuotaPlataformaItem>> cargarMia(String usuarioId) async {
    final rows = await _client
        .from('cuotas_plataforma')
        .select(
            'id, usuario_id, organizacion_id, mes, anio, monto, estado, fecha_vencimiento, fecha_pago, comprobante_url, metodo_pago, motivo')
        .eq('usuario_id', usuarioId)
        .order('anio', ascending: false)
        .order('mes', ascending: false);
    return (rows as List).map((r) => CuotaPlataformaItem.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// El usuario reporta que ya pagó su cuota de plataforma -- mismo
  /// patrón que ConductorService.reportarPago para cuotas_mensuales: si
  /// fue transferencia hace falta comprobante, el estado pasa a
  /// 'pagado' de una (reforzado en la base por el trigger de
  /// autoservicio), y no puede tocar ningún otro dato de la cuota. Usa
  /// el mismo bucket "comprobantes" (con prefijo "plataforma_" en el
  /// nombre de archivo para no mezclarse con los de cuotas_mensuales
  /// que ya viven en la misma carpeta {orgId}/{usuarioId}/) -- las
  /// políticas de storage ya cubren esta ruta.
  Future<void> reportarPago({
    required String cuotaId,
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
        path = '$organizacionId/$usuarioId/plataforma_$cuotaId.$extension';
        await _client.storage.from(_bucket).uploadBinary(
              path,
              bytes!,
              fileOptions: FileOptions(upsert: true, contentType: _contentType(extension!)),
            );
      }
      await _client.from('cuotas_plataforma').update({
        if (path != null) 'comprobante_url': path,
        'metodo_pago': metodoPago,
        'fecha_pago': _formatoFecha(fechaPago),
        'estado': 'pagado',
      }).eq('id', cuotaId);
    } on CuotaPlataformaException {
      rethrow;
    } catch (_) {
      throw CuotaPlataformaException('No se pudo registrar el pago. Intentá de nuevo.');
    }
  }

  Future<String> obtenerUrlComprobante(String path) {
    return _client.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  /// Solo el dueño de plataforma: genera el cargo del mes para todos
  /// los presidentes de asociación, presidentes de parada y
  /// conductores de una organización (se derivan de `usuarios`, no de
  /// `conductores`, así también entra un presidente que no tiene fila
  /// ahí todavía). Usa upsert con ignoreDuplicates para no romper si
  /// algunos ya tenían el cargo de ese mes cargado (unique
  /// usuario_id+mes+anio+motivo).
  Future<int> generarCargoMensual({
    required String organizacionId,
    required int mes,
    required int anio,
    required double monto,
    required DateTime fechaVencimiento,
    required String creadoPor,
  }) async {
    final usuarios = await _client
        .from('usuarios')
        .select('id')
        .eq('organizacion_id', organizacionId)
        .inFilter('rol', ['presidente_asociacion', 'presidente_parada', 'conductor']);

    final lista = usuarios as List;
    if (lista.isEmpty) {
      throw CuotaPlataformaException('No hay miembros en esta organización todavía.');
    }

    final filas = lista.map((u) {
      final id = (u as Map<String, dynamic>)['id'] as String;
      return {
        'usuario_id': id,
        'mes': mes,
        'anio': anio,
        'monto': monto,
        'fecha_vencimiento': _formatoFecha(fechaVencimiento),
        'registrado_por': creadoPor,
        'motivo': 'Cuota de plataforma',
      };
    }).toList();

    try {
      await _client
          .from('cuotas_plataforma')
          .upsert(filas, onConflict: 'usuario_id,mes,anio,motivo', ignoreDuplicates: true);
    } catch (_) {
      throw CuotaPlataformaException('No se pudo generar el cargo del mes. Intentá de nuevo.');
    }
    return filas.length;
  }

  /// Override manual del dueño de plataforma (marcar pagado a mano,
  /// exonerar, o revertir a pendiente/atrasado).
  Future<void> marcarEstado({required String cuotaId, required String estado}) async {
    await _client.from('cuotas_plataforma').update({'estado': estado}).eq('id', cuotaId);
  }

  /// Todas las cuotas de una organización, con nombre/rol del usuario y
  /// su parada (si es conductor, la suya; si preside una parada, la que
  /// preside) -- para el panel del dueño y la vista de solo lectura del
  /// presidente de asociación. Agregación en cliente, mismo patrón que
  /// balance_pagos.dart.
  Future<List<CuotaPlataformaItem>> cargarPorOrganizacion(String organizacionId) async {
    // cuotas_plataforma tiene DOS FK a usuarios (usuario_id y
    // registrado_por) -- hay que decirle a PostgREST cuál de las dos
    // usar acá, si no tira PGRST201 ("more than one relationship").
    final cuotasFuture = _client
        .from('cuotas_plataforma')
        .select(
            'id, usuario_id, organizacion_id, mes, anio, monto, estado, fecha_vencimiento, fecha_pago, comprobante_url, metodo_pago, motivo, usuarios!cuotas_plataforma_usuario_id_fkey(nombre, rol)')
        .eq('organizacion_id', organizacionId)
        .order('anio', ascending: false)
        .order('mes', ascending: false);
    final conductoresFuture =
        _client.from('conductores').select('usuario_id, parada_id, paradas(nombre)').eq(
              'organizacion_id',
              organizacionId,
            );
    final paradasFuture = _client
        .from('paradas')
        .select('id, nombre, presidente_id')
        .eq('organizacion_id', organizacionId);

    final resultados = await Future.wait([cuotasFuture, conductoresFuture, paradasFuture]);
    final cuotasRaw = resultados[0] as List;
    final conductoresRaw = resultados[1] as List;
    final paradasRaw = resultados[2] as List;

    // usuario_id de conductor -> (paradaId, paradaNombre)
    final paradaPorConductor = <String, MapEntry<String, String?>>{};
    for (final c in conductoresRaw) {
      final map = c as Map<String, dynamic>;
      final parada = map['paradas'] as Map<String, dynamic>?;
      paradaPorConductor[map['usuario_id'] as String] =
          MapEntry(map['parada_id'] as String, parada?['nombre'] as String?);
    }
    // usuario_id de presidente -> (paradaId, paradaNombre) de la que preside
    final paradaPorPresidente = <String, MapEntry<String, String?>>{};
    for (final p in paradasRaw) {
      final map = p as Map<String, dynamic>;
      final presidenteId = map['presidente_id'] as String?;
      if (presidenteId != null) {
        paradaPorPresidente[presidenteId] = MapEntry(map['id'] as String, map['nombre'] as String?);
      }
    }

    return cuotasRaw.map((r) {
      final item = CuotaPlataformaItem.fromMap(r as Map<String, dynamic>);
      final porConductor = paradaPorConductor[item.usuarioId];
      final porPresidente = paradaPorPresidente[item.usuarioId];
      final parada = porConductor ?? porPresidente;
      if (parada == null) return item;
      return item.copyWithParada(paradaId: parada.key, paradaNombre: parada.value);
    }).toList();
  }

  /// Agrupa una lista ya cargada (ver [cargarPorOrganizacion]) por
  /// parada -- helper compartido entre la vista del dueño y la del
  /// presidente de asociación.
  List<GrupoCuotasPorParada> agruparPorParada(List<CuotaPlataformaItem> cuotas) {
    final grupos = <String, List<CuotaPlataformaItem>>{};
    final nombres = <String, String?>{};
    for (final c in cuotas) {
      final clave = c.paradaId ?? '__sin_parada__';
      nombres[clave] = c.paradaNombre;
      grupos.putIfAbsent(clave, () => []).add(c);
    }
    final lista = grupos.entries
        .map((e) => GrupoCuotasPorParada(
              paradaId: e.key == '__sin_parada__' ? null : e.key,
              paradaNombre: nombres[e.key],
              cuotas: e.value,
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
