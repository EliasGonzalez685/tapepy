import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

/// Las únicas dos fotos que pide el vehículo: de frente (con la chapa
/// legible) y de lejos (se aprecia el vehículo completo).
enum VehiculoFotoSlot { frente, lejos }

extension VehiculoFotoSlotInfo on VehiculoFotoSlot {
  String get columna {
    switch (this) {
      case VehiculoFotoSlot.frente:
        return 'foto_frente_chapa';
      case VehiculoFotoSlot.lejos:
        return 'foto_lejos';
    }
  }

  String get nombreArchivo {
    switch (this) {
      case VehiculoFotoSlot.frente:
        return 'frente';
      case VehiculoFotoSlot.lejos:
        return 'lejos';
    }
  }

  String get etiqueta {
    switch (this) {
      case VehiculoFotoSlot.frente:
        return 'Frente (que se vea la chapa)';
      case VehiculoFotoSlot.lejos:
        return 'De lejos (vehículo completo)';
    }
  }
}

class VehiculoInfo {
  final String? id;
  final String? marca;
  final String? modelo;
  final int? anio;
  final String? chapa;
  final String? color;
  final String? resolucionNumero;
  final String? fotoFrenteChapa;
  final String? fotoLejos;
  // Si este vehículo entra o no en los listados imprimibles — un
  // conductor puede tener más de un vehículo habilitado (o ninguno) a
  // la vez; lo alterna el propio conductor o cualquiera de sus dos
  // presidentes (ver migración 0029 y su trigger de blindaje).
  final bool incluirEnListado;

  VehiculoInfo({
    this.id,
    this.marca,
    this.modelo,
    this.anio,
    this.chapa,
    this.color,
    this.resolucionNumero,
    this.fotoFrenteChapa,
    this.fotoLejos,
    this.incluirEnListado = true,
  });

  bool get estaVacio => marca == null && modelo == null && chapa == null;

  VehiculoInfo copyWith({bool? incluirEnListado}) {
    return VehiculoInfo(
      id: id,
      marca: marca,
      modelo: modelo,
      anio: anio,
      chapa: chapa,
      color: color,
      resolucionNumero: resolucionNumero,
      fotoFrenteChapa: fotoFrenteChapa,
      fotoLejos: fotoLejos,
      incluirEnListado: incluirEnListado ?? this.incluirEnListado,
    );
  }

  factory VehiculoInfo.fromMap(Map<String, dynamic> map) {
    return VehiculoInfo(
      id: map['id'] as String?,
      marca: map['marca'] as String?,
      modelo: map['modelo'] as String?,
      anio: (map['anio'] as num?)?.toInt(),
      chapa: map['chapa'] as String?,
      color: map['color'] as String?,
      resolucionNumero: map['resolucion_numero'] as String?,
      fotoFrenteChapa: map['foto_frente_chapa'] as String?,
      fotoLejos: map['foto_lejos'] as String?,
      incluirEnListado: map['incluir_en_listado'] as bool? ?? true,
    );
  }
}

class ConductorPerfil {
  final String conductorId;
  final String usuarioId;
  final String organizacionId;
  final String? turno;
  final String paradaId;
  final String paradaNombre;
  // Un conductor (o presidente que también es socio) puede tener más
  // de un vehículo — ver [[project_traude_multivehiculo]]. Lista vacía
  // = todavía no cargó ninguno.
  final List<VehiculoInfo> vehiculos;

  ConductorPerfil({
    required this.conductorId,
    required this.usuarioId,
    required this.organizacionId,
    required this.paradaId,
    required this.paradaNombre,
    this.turno,
    this.vehiculos = const [],
  });

  /// Texto corto para la tarjeta "Mi vehículo"/"Mis vehículos" en las
  /// pantallas de acceso rápido — resume sin listar todo.
  String get resumenVehiculos {
    final cargados = vehiculos.where((v) => !v.estaVacio).toList();
    if (cargados.isEmpty) return 'Todavía no cargaste los datos';
    if (cargados.length == 1) {
      final v = cargados.first;
      return '${v.marca ?? ''} ${v.modelo ?? ''} · ${v.chapa ?? ''}';
    }
    return '${cargados.length} vehículos registrados';
  }
}

class DocumentoConductorItem {
  final String id;
  final String categoria; // personal | vehiculo
  final String tipo;
  final String estado;
  final DateTime? fechaVencimiento;
  final String archivoUrl;
  final String? nombreArchivo;
  // Texto libre para documentos que no entran en la lista fija de
  // tipos (tipo == 'otro') — así queda claro qué es sin adivinar.
  final String? descripcion;

  DocumentoConductorItem({
    required this.id,
    required this.categoria,
    required this.tipo,
    required this.estado,
    required this.archivoUrl,
    this.fechaVencimiento,
    this.nombreArchivo,
    this.descripcion,
  });

  factory DocumentoConductorItem.fromMap(Map<String, dynamic> map) {
    return DocumentoConductorItem(
      id: map['id'] as String,
      categoria: map['categoria'] as String,
      tipo: map['tipo'] as String,
      estado: map['estado'] as String,
      archivoUrl: map['archivo_url'] as String,
      nombreArchivo: map['nombre_archivo'] as String?,
      descripcion: map['descripcion'] as String?,
      fechaVencimiento: map['fecha_vencimiento'] != null
          ? DateTime.parse(map['fecha_vencimiento'] as String)
          : null,
    );
  }
}

class CuotaException implements Exception {
  final String message;
  CuotaException(this.message);
  @override
  String toString() => message;
}

class CuotaPropia {
  final String id;
  final int mes;
  final int anio;
  final double montoTotal;
  final String estado;
  final String motivo;
  final DateTime fechaVencimiento;
  final DateTime? fechaPago;
  final String? comprobanteUrl;
  final String? loteId;
  final String? metodoPago;

  CuotaPropia({
    required this.id,
    required this.mes,
    required this.anio,
    required this.montoTotal,
    required this.estado,
    required this.motivo,
    required this.fechaVencimiento,
    this.fechaPago,
    this.comprobanteUrl,
    this.loteId,
    this.metodoPago,
  });

  factory CuotaPropia.fromMap(Map<String, dynamic> map) {
    return CuotaPropia(
      id: map['id'] as String,
      mes: (map['mes'] as num).toInt(),
      anio: (map['anio'] as num).toInt(),
      montoTotal: (map['monto_total'] as num).toDouble(),
      estado: map['estado'] as String,
      motivo: map['motivo'] as String? ?? 'Pago mensual',
      fechaVencimiento: DateTime.parse(map['fecha_vencimiento'] as String),
      fechaPago: map['fecha_pago'] != null ? DateTime.parse(map['fecha_pago'] as String) : null,
      comprobanteUrl: map['comprobante_url'] as String?,
      loteId: map['lote_id'] as String?,
      metodoPago: map['metodo_pago'] as String?,
    );
  }
}

/// Todo lo que un conductor gestiona de sí mismo: su fila en
/// `conductores` (la asigna el presidente, acá solo se lee), su
/// vehículo, sus documentos (los sube él, nadie más) y sus cuotas — el
/// presidente las carga, pero el conductor puede reportar que ya pagó
/// adjuntando su comprobante (ver reportarPago).
class ConductorService {
  final _client = SupabaseConfig.client;
  static const _bucket = 'documentos';

  /// null si el usuario todavía no fue asignado a ninguna parada (tarea
  /// del presidente de asociación, no del conductor).
  Future<ConductorPerfil?> cargarPerfil(String usuarioId) async {
    final rows = await _client
        .from('conductores')
        .select(
            'id, organizacion_id, turno, parada_id, paradas(nombre), vehiculos(id, marca, modelo, anio, chapa, color, resolucion_numero, foto_frente_chapa, foto_lejos, incluir_en_listado)')
        .eq('usuario_id', usuarioId)
        .limit(1);

    final lista = rows as List;
    if (lista.isEmpty) return null;
    final row = lista.first as Map<String, dynamic>;

    final parada = row['paradas'] as Map<String, dynamic>?;
    // Postgrest devuelve `vehiculos` como lista ahora que un conductor
    // puede tener más de uno (el FK conductor_id ya no es UNIQUE).
    final vehiculosRaw = row['vehiculos'];
    final vehiculos = (vehiculosRaw is List ? vehiculosRaw : <dynamic>[])
        .map((v) => VehiculoInfo.fromMap(v as Map<String, dynamic>))
        .toList();

    return ConductorPerfil(
      conductorId: row['id'] as String,
      usuarioId: usuarioId,
      organizacionId: row['organizacion_id'] as String,
      turno: row['turno'] as String?,
      paradaId: row['parada_id'] as String,
      paradaNombre: parada?['nombre'] as String? ?? 'Sin asignar',
      vehiculos: vehiculos,
    );
  }

  /// Un presidente (de parada o de asociación) también es, además de su
  /// rol de representación, un socio más de una parada — con su propio
  /// vehículo y documentos, igual que cualquier conductor. Esto activa
  /// esa parte de su perfil creando la fila en `conductores` (RLS ya
  /// permite que cualquier usuario autenticado se inserte a sí mismo:
  /// política `conductores_propio_write`, `usuario_id = auth.uid()`).
  /// Después de esto, [cargarPerfil] ya le devuelve datos.
  Future<void> crearPerfilPropio({
    required String organizacionId,
    required String paradaId,
    required String usuarioId,
  }) async {
    await _client.from('conductores').insert({
      'organizacion_id': organizacionId,
      'usuario_id': usuarioId,
      'parada_id': paradaId,
    });
  }

  /// Crea una fila de vehículo vacía — la primera vez que el conductor
  /// entra a "Mis vehículos" (para tener un id y poder subir fotos
  /// aunque todavía no haya cargado marca/modelo/etc.) o cada vez que
  /// agrega uno adicional. Un conductor puede tener más de un vehículo
  /// (ver [[project_traude_multivehiculo]]).
  Future<String> agregarVehiculo({
    required String conductorId,
    required String organizacionId,
  }) async {
    final row = await _client
        .from('vehiculos')
        .insert({'organizacion_id': organizacionId, 'conductor_id': conductorId})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> actualizarVehiculo({
    required String vehiculoId,
    String? marca,
    String? modelo,
    int? anio,
    String? chapa,
    String? color,
    String? resolucionNumero,
  }) async {
    await _client.from('vehiculos').update({
      'marca': marca,
      'modelo': modelo,
      'anio': anio,
      'chapa': chapa,
      'color': color,
      'resolucion_numero': resolucionNumero,
    }).eq('id', vehiculoId);
  }

  /// Si este vehículo entra o no en los próximos listados imprimibles.
  /// Lo puede tocar el propio conductor o cualquiera de sus dos
  /// presidentes (RLS + trigger de blindaje, ver migración 0029) — es
  /// la única columna que un presidente puede cambiar acá.
  Future<void> alternarIncluirEnListado({
    required String vehiculoId,
    required bool valor,
  }) async {
    await _client.from('vehiculos').update({'incluir_en_listado': valor}).eq('id', vehiculoId);
  }

  /// Elimina el vehículo por completo (y sus fotos del storage, si
  /// tenía). Solo el propio conductor puede hacerlo (RLS).
  Future<void> eliminarVehiculo({
    required String vehiculoId,
    String? fotoFrenteChapa,
    String? fotoLejos,
  }) async {
    await _client.from('vehiculos').delete().eq('id', vehiculoId);
    final paths = [fotoFrenteChapa, fotoLejos].whereType<String>().toList();
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from(_bucket).remove(paths);
      } catch (_) {
        // La fila ya se borró; si falla la limpieza de storage no es
        // motivo para que la operación completa se vea como un error.
      }
    }
  }

  /// Sube una de las dos fotos fijas del vehículo (frente con chapa
  /// visible, o de lejos completo) al bucket privado de documentos, en
  /// una carpeta propia por vehículo (para no pisar la foto de otro
  /// vehículo del mismo conductor). Cada slot siempre usa el mismo
  /// nombre de archivo dentro de esa carpeta (se reemplaza si ya
  /// existía una foto ahí).
  Future<String> subirFotoVehiculo({
    required String organizacionId,
    required String usuarioId,
    required String vehiculoId,
    required VehiculoFotoSlot slot,
    required Uint8List bytes,
    required String extension,
  }) async {
    final path = '$organizacionId/$usuarioId/$vehiculoId/vehiculo_${slot.nombreArchivo}.$extension';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: _contentType(extension)),
        );

    await _client.from('vehiculos').update({slot.columna: path}).eq('id', vehiculoId);

    return path;
  }

  Future<void> eliminarFotoVehiculo({
    required String vehiculoId,
    required VehiculoFotoSlot slot,
    required String path,
  }) async {
    await _client.from('vehiculos').update({slot.columna: null}).eq('id', vehiculoId);
    await _client.storage.from(_bucket).remove([path]);
  }

  /// El bucket "documentos" es privado — hace falta una URL firmada para
  /// poder mostrar la miniatura en la app.
  Future<String> obtenerUrlFirmada(String path) async {
    return _client.storage.from(_bucket).createSignedUrl(path, 3600);
  }

  Future<List<DocumentoConductorItem>> cargarDocumentos(String conductorId) async {
    final rows = await _client
        .from('documentos_conductor')
        .select('id, categoria, tipo, estado, fecha_vencimiento, archivo_url, nombre_archivo, descripcion')
        .eq('conductor_id', conductorId)
        .order('subido_en', ascending: false);
    return (rows as List)
        .map((r) => DocumentoConductorItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Sube el archivo a `documentos/{organizacionId}/{usuarioId}/...` (así
  /// lo puede leer el presidente de la misma organización, pero solo el
  /// propio conductor puede escribir ahí) y crea la fila en
  /// `documentos_conductor`. El estado se calcula acá mismo según la
  /// fecha de vencimiento declarada (no hay verificación automática
  /// todavía, eso queda para más adelante).
  Future<void> subirDocumento({
    required String organizacionId,
    required String usuarioId,
    required String conductorId,
    required String categoria,
    required String tipo,
    required Uint8List bytes,
    required String extension,
    DateTime? fechaVencimiento,
    String? descripcion,
  }) async {
    final nombreArchivo = '${tipo}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final path = '$organizacionId/$usuarioId/$nombreArchivo';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: _contentType(extension)),
        );

    final estado = _estadoSegunVencimiento(fechaVencimiento);

    await _client.from('documentos_conductor').insert({
      'organizacion_id': organizacionId,
      'conductor_id': conductorId,
      'categoria': categoria,
      'tipo': tipo,
      'archivo_url': path,
      'nombre_archivo': nombreArchivo,
      'fecha_vencimiento':
          fechaVencimiento != null ? _formatoFecha(fechaVencimiento) : null,
      'estado': estado,
      'descripcion': descripcion,
    });
  }

  Future<List<CuotaPropia>> cargarCuotas(String usuarioId) async {
    final rows = await _client
        .from('cuotas_mensuales')
        .select(
            'id, mes, anio, monto_total, estado, motivo, fecha_vencimiento, fecha_pago, comprobante_url, lote_id, metodo_pago')
        .eq('usuario_id', usuarioId)
        .order('anio', ascending: false)
        .order('mes', ascending: false);
    return (rows as List).map((r) => CuotaPropia.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// El conductor reporta que ya pagó una cuota, indicando el medio de
  /// pago. Si fue por transferencia hace falta adjuntar el comprobante
  /// (sube el archivo a `comprobantes/{orgId}/{usuarioId}/{cuotaId}.ext`,
  /// bucket privado); si fue en efectivo no hace falta nada más — el
  /// presidente confirma ese pago a mano cuando corresponda. El estado
  /// pasa a 'pagado' automáticamente (reforzado también en la base, ver
  /// trigger cuotas_proteger_autoservicio); no puede tocar el monto ni
  /// ningún otro dato de la cuota.
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
      throw CuotaException('Adjuntá el comprobante de la transferencia.');
    }
    try {
      String? path;
      if (metodoPago == 'transferencia') {
        path = '$organizacionId/$usuarioId/$cuotaId.$extension';
        await _client.storage.from('comprobantes').uploadBinary(
              path,
              bytes!,
              fileOptions: FileOptions(upsert: true, contentType: _contentType(extension!)),
            );
      }
      await _client.from('cuotas_mensuales').update({
        if (path != null) 'comprobante_url': path,
        'metodo_pago': metodoPago,
        'fecha_pago': _formatoFecha(fechaPago),
        'estado': 'pagado',
      }).eq('id', cuotaId);
    } on CuotaException {
      rethrow;
    } catch (_) {
      throw CuotaException('No se pudo registrar el pago. Intentá de nuevo.');
    }
  }

  Future<String> obtenerUrlComprobante(String path) {
    return _client.storage.from('comprobantes').createSignedUrl(path, 3600);
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
