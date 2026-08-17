import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../conductor/data/conductor_service.dart' show VehiculoInfo;

/// Modelos y servicio para la pantalla de detalle de una parada
/// (rol presidente de asociación). Cada sección (conductores, cuotas,
/// documentos, incidentes) se carga por separado para que la pantalla
/// pueda mostrar cada pestaña independientemente.

class CuotaException implements Exception {
  final String message;
  CuotaException(this.message);
  @override
  String toString() => message;
}

class IncidenteException implements Exception {
  final String message;
  IncidenteException(this.message);
  @override
  String toString() => message;
}

class ConductorItem {
  final String id;
  final String usuarioId;
  final String nombre;
  final String? telefono;
  final String? turno;
  final String? vehiculoDescripcion;
  final String? chapa;
  // Resolución Nº INDIVIDUAL del conductor (usuarios.resolucion_individual)
  // — no es por vehículo, es por persona. Distinta de la resolución de
  // la parada (ver ParadaResumen.resolucionNumero).
  final String? resolucionNumero;
  final bool enServicio;

  ConductorItem({
    required this.id,
    required this.usuarioId,
    required this.nombre,
    this.telefono,
    this.turno,
    this.vehiculoDescripcion,
    this.chapa,
    this.resolucionNumero,
    this.enServicio = false,
  });

  factory ConductorItem.fromMap(Map<String, dynamic> map) {
    final usuario = map['usuarios'] as Map<String, dynamic>?;
    // Postgrest devuelve `vehiculos` como lista (un conductor puede
    // tener más de uno) — acá es solo un resumen rápido en pantalla,
    // no el listado imprimible, así que mostramos el primero y, si hay
    // más, lo indicamos sin desglosar todos.
    final vehiculosRaw = map['vehiculos'];
    final vehiculos =
        (vehiculosRaw is List ? vehiculosRaw : <dynamic>[]).cast<Map<String, dynamic>>();
    final vehiculo = vehiculos.isNotEmpty ? vehiculos.first : null;
    String? vehiculoDesc;
    if (vehiculo != null) {
      final marca = vehiculo['marca'] as String?;
      final modelo = vehiculo['modelo'] as String?;
      vehiculoDesc = [marca, modelo].where((e) => e != null && e.isNotEmpty).join(' ');
      if (vehiculoDesc.isEmpty) vehiculoDesc = null;
      if (vehiculos.length > 1) {
        vehiculoDesc = vehiculoDesc == null
            ? '${vehiculos.length} vehículos'
            : '$vehiculoDesc (+${vehiculos.length - 1})';
      }
    }
    return ConductorItem(
      id: map['id'] as String,
      usuarioId: map['usuario_id'] as String,
      nombre: usuario?['nombre'] as String? ?? 'Sin nombre',
      telefono: usuario?['telefono'] as String?,
      turno: map['turno'] as String?,
      vehiculoDescripcion: vehiculoDesc,
      chapa: vehiculo?['chapa'] as String?,
      resolucionNumero: usuario?['resolucion_individual'] as String?,
      enServicio: usuario?['en_servicio'] as bool? ?? false,
    );
  }
}

/// Alta de conductor todavía sin aprobar por el presidente
/// correspondiente (usuarios.cuenta_confirmada = false). Sin aprobar,
/// el conductor no puede ni siquiera iniciar sesión.
class SolicitudPendienteItem {
  final String usuarioId;
  final String nombre;
  final String? cedula;
  final String? telefono;
  final String? paradaNombre; // solo se completa en el listado de asociación
  final DateTime creadoEn;

  SolicitudPendienteItem({
    required this.usuarioId,
    required this.nombre,
    required this.creadoEn,
    this.cedula,
    this.telefono,
    this.paradaNombre,
  });

  factory SolicitudPendienteItem.fromMap(Map<String, dynamic> map) {
    final usuario = map['usuarios'] as Map<String, dynamic>;
    final parada = map['paradas'] as Map<String, dynamic>?;
    return SolicitudPendienteItem(
      usuarioId: usuario['id'] as String,
      nombre: usuario['nombre'] as String? ?? 'Sin nombre',
      cedula: usuario['cedula'] as String?,
      telefono: usuario['telefono'] as String?,
      paradaNombre: parada?['nombre'] as String?,
      creadoEn: DateTime.parse(usuario['creado_en'] as String),
    );
  }
}

class CuotaItem {
  final String id;
  final String usuarioId;
  final String usuarioNombre;
  final int mes;
  final int anio;
  final double montoTotal;
  final String estado;
  final String motivo;
  final DateTime fechaVencimiento;
  final String? loteId;
  final String? metodoPago;

  CuotaItem({
    required this.id,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.mes,
    required this.anio,
    required this.montoTotal,
    required this.estado,
    required this.motivo,
    required this.fechaVencimiento,
    this.loteId,
    this.metodoPago,
  });

  factory CuotaItem.fromMap(Map<String, dynamic> map) {
    final usuario = map['usuarios'] as Map<String, dynamic>?;
    return CuotaItem(
      id: map['id'] as String,
      usuarioId: map['usuario_id'] as String,
      usuarioNombre: usuario?['nombre'] as String? ?? 'Sin nombre',
      mes: (map['mes'] as num).toInt(),
      anio: (map['anio'] as num).toInt(),
      montoTotal: (map['monto_total'] as num).toDouble(),
      estado: map['estado'] as String,
      motivo: map['motivo'] as String? ?? 'Pago mensual',
      fechaVencimiento: DateTime.parse(map['fecha_vencimiento'] as String),
      loteId: map['lote_id'] as String?,
      metodoPago: map['metodo_pago'] as String?,
    );
  }
}

class DocumentoItem {
  final String id;
  final String entidad; // nombre del conductor, o "Parada"
  final String tipo;
  final String estado;
  final DateTime? fechaVencimiento;
  final String archivoUrl;
  final String? nombreArchivo;
  final String? descripcion;

  DocumentoItem({
    required this.id,
    required this.entidad,
    required this.tipo,
    required this.estado,
    required this.archivoUrl,
    this.fechaVencimiento,
    this.nombreArchivo,
    this.descripcion,
  });
}

class IncidenteItem {
  final String id;
  final String descripcion;
  final String tipo;
  final String estado;
  final DateTime creadoEn;

  IncidenteItem({
    required this.id,
    required this.descripcion,
    required this.tipo,
    required this.estado,
    required this.creadoEn,
  });

  factory IncidenteItem.fromMap(Map<String, dynamic> map) {
    return IncidenteItem(
      id: map['id'] as String,
      descripcion: map['descripcion'] as String,
      tipo: map['tipo'] as String,
      estado: map['estado'] as String,
      creadoEn: DateTime.parse(map['creado_en'] as String),
    );
  }
}

/// Fila de datos para el listado imprimible de conductores/asociados —
/// trae todo lo que las columnas seleccionables puedan necesitar
/// (imprimir_listado_screen.dart decide cuáles mostrar).
class ConductorListadoItem {
  final String nombre;
  final String? cedula;
  final String? telefono;
  final String? paradaId;
  final String? paradaNombre;
  final String? turno;
  final String? chapa;
  final String? marca;
  final String? modelo;
  final int? anio;
  final String? color;
  // Dos resoluciones distintas, ambas para no confundir en el listado:
  // la del conductor (persona, usuarios.resolucion_individual) y la de
  // la parada (paradas.resolucion_numero), que puede variar por parada.
  final String? resolucionIndividual;
  final String? resolucionParada;

  ConductorListadoItem({
    required this.nombre,
    this.cedula,
    this.telefono,
    this.paradaId,
    this.paradaNombre,
    this.turno,
    this.chapa,
    this.marca,
    this.modelo,
    this.anio,
    this.color,
    this.resolucionIndividual,
    this.resolucionParada,
  });

  /// Un conductor puede tener más de un vehículo (ver
  /// [[project_traude_multivehiculo]]) y cada uno decide si entra en
  /// los listados impresos (`incluir_en_listado`). Por eso una sola
  /// fila de `conductores` puede volverse 0, 1 o varias filas de
  /// listado — una por cada vehículo habilitado, repitiendo los datos
  /// de la persona. Si no tiene ningún vehículo habilitado (o
  /// directamente no cargó ninguno), sale una sola fila sin datos de
  /// vehículo, igual que antes de que existiera esta función.
  static List<ConductorListadoItem> listaDesdeFila(Map<String, dynamic> map) {
    final usuario = map['usuarios'] as Map<String, dynamic>?;
    final parada = map['paradas'] as Map<String, dynamic>?;
    final vehiculosRaw = map['vehiculos'];
    final vehiculos = (vehiculosRaw is List ? vehiculosRaw : <dynamic>[])
        .cast<Map<String, dynamic>>()
        .where((v) => v['incluir_en_listado'] != false)
        .toList();

    final nombre = usuario?['nombre'] as String? ?? 'Sin nombre';
    final cedula = usuario?['cedula'] as String?;
    final telefono = usuario?['telefono'] as String?;
    final resolucionIndividual = usuario?['resolucion_individual'] as String?;
    final paradaId = parada?['id'] as String?;
    final paradaNombre = parada?['nombre'] as String?;
    final resolucionParada = parada?['resolucion_numero'] as String?;
    final turno = map['turno'] as String?;

    if (vehiculos.isEmpty) {
      return [
        ConductorListadoItem(
          nombre: nombre,
          cedula: cedula,
          telefono: telefono,
          paradaId: paradaId,
          paradaNombre: paradaNombre,
          turno: turno,
          resolucionIndividual: resolucionIndividual,
          resolucionParada: resolucionParada,
        ),
      ];
    }

    return vehiculos
        .map((vehiculo) => ConductorListadoItem(
              nombre: nombre,
              cedula: cedula,
              telefono: telefono,
              paradaId: paradaId,
              paradaNombre: paradaNombre,
              turno: turno,
              chapa: vehiculo['chapa'] as String?,
              marca: vehiculo['marca'] as String?,
              modelo: vehiculo['modelo'] as String?,
              anio: (vehiculo['anio'] as num?)?.toInt(),
              color: vehiculo['color'] as String?,
              resolucionIndividual: resolucionIndividual,
              resolucionParada: resolucionParada,
            ))
        .toList();
  }
}

class ParadaDetalleService {
  final _client = SupabaseConfig.client;

  /// Listado completo (una parada) para el presidente de esa parada —
  /// pensado para el selector de columnas del PDF imprimible.
  Future<List<ConductorListadoItem>> cargarListadoConductores(String paradaId) async {
    final rows = await _client
        .from('conductores')
        .select(
            'turno, usuarios(nombre, cedula, telefono, resolucion_individual), paradas(id, nombre, resolucion_numero), vehiculos(marca, modelo, anio, color, chapa, incluir_en_listado)')
        .eq('parada_id', paradaId);
    final items = (rows as List)
        .expand((r) => ConductorListadoItem.listaDesdeFila(r as Map<String, dynamic>))
        .toList();
    items.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return items;
  }

  /// Listado completo de TODAS las paradas de la organización — para el
  /// presidente de asociación (incluye a qué parada pertenece cada
  /// conductor). La RLS ya scopea por organización para ese rol; el
  /// dueño de plataforma en cambio ve todas las organizaciones, así que
  /// necesita el filtro explícito para pararse en una sola.
  Future<List<ConductorListadoItem>> cargarListadoConductoresOrganizacion({
    String? organizacionId,
  }) async {
    var query = _client.from('conductores').select(
        'turno, paradas(id, nombre, resolucion_numero), usuarios(nombre, cedula, telefono, resolucion_individual), vehiculos(marca, modelo, anio, color, chapa, incluir_en_listado)');
    if (organizacionId != null) {
      query = query.eq('organizacion_id', organizacionId);
    }
    final rows = await query;
    final items = (rows as List)
        .expand((r) => ConductorListadoItem.listaDesdeFila(r as Map<String, dynamic>))
        .toList();
    items.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return items;
  }

  Future<Map<String, dynamic>> cargarParada(String paradaId) async {
    final row = await _client
        .from('paradas')
        .select('id, nombre, ubicacion')
        .eq('id', paradaId)
        .single();
    return row;
  }

  /// Vehículos de un conductor puntual — para que el presidente (de
  /// parada o de asociación) pueda ver el detalle y alternar cuáles
  /// entran en los listados impresos. La RLS de `vehiculos` ya permite
  /// que ambos presidentes hagan ese UPDATE puntual (ver migración
  /// 0029); todo lo demás del vehículo queda blindado por el trigger.
  Future<List<VehiculoInfo>> cargarVehiculosDeConductor(String conductorId) async {
    final rows = await _client
        .from('vehiculos')
        .select(
            'id, marca, modelo, anio, chapa, color, foto_frente_chapa, foto_lejos, incluir_en_listado')
        .eq('conductor_id', conductorId);
    return (rows as List).map((r) => VehiculoInfo.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> alternarVehiculoEnListado({
    required String vehiculoId,
    required bool valor,
  }) async {
    await _client.from('vehiculos').update({'incluir_en_listado': valor}).eq('id', vehiculoId);
  }

  Future<List<ConductorItem>> cargarConductores(String paradaId) async {
    final rows = await _client
        .from('conductores')
        .select(
            'id, usuario_id, turno, usuarios(nombre, telefono, en_servicio, resolucion_individual), vehiculos(marca, modelo, chapa)')
        .eq('parada_id', paradaId);
    return (rows as List)
        .map((r) => ConductorItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Altas pendientes de aprobación en una sola parada (presidente de
  /// esa parada).
  Future<List<SolicitudPendienteItem>> cargarSolicitudesPendientes(String paradaId) async {
    final rows = await _client
        .from('conductores')
        .select('usuarios!inner(id, nombre, cedula, telefono, creado_en, cuenta_confirmada)')
        .eq('parada_id', paradaId)
        .eq('usuarios.cuenta_confirmada', false);
    final items = (rows as List)
        .map((r) => SolicitudPendienteItem.fromMap(r as Map<String, dynamic>))
        .toList();
    items.sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
    return items;
  }

  /// Altas pendientes de TODAS las paradas de la organización
  /// (presidente de asociación) — incluye a qué parada corresponde
  /// cada una. El dueño de plataforma pasa [organizacionId] para
  /// acotar a una sola organización (por RLS ve todas juntas).
  Future<List<SolicitudPendienteItem>> cargarSolicitudesPendientesOrganizacion({
    String? organizacionId,
  }) async {
    var query = _client
        .from('conductores')
        .select(
            'paradas(nombre), usuarios!inner(id, nombre, cedula, telefono, creado_en, cuenta_confirmada)')
        .eq('usuarios.cuenta_confirmada', false);
    if (organizacionId != null) {
      query = query.eq('organizacion_id', organizacionId);
    }
    final rows = await query;
    final items = (rows as List)
        .map((r) => SolicitudPendienteItem.fromMap(r as Map<String, dynamic>))
        .toList();
    items.sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
    return items;
  }

  Future<void> aprobarConductor(String usuarioId) async {
    await _client.from('usuarios').update({'cuenta_confirmada': true}).eq('id', usuarioId);
  }

  /// Elimina la cuenta del conductor por completo (usuarios + todo lo
  /// que depende de esa fila: conductores, vehículo, documentos, cuotas,
  /// mensajes — todo con ON DELETE CASCADE). Sirve tanto para rechazar
  /// una solicitud pendiente como para dar de baja a un conductor ya
  /// aprobado.
  Future<void> eliminarConductor(String usuarioId) async {
    await _client.from('usuarios').delete().eq('id', usuarioId);
  }

  Future<List<CuotaItem>> cargarCuotas(String paradaId) async {
    final rows = await _client
        .from('cuotas_mensuales')
        .select(
            'id, usuario_id, mes, anio, monto_total, estado, motivo, fecha_vencimiento, lote_id, metodo_pago, usuarios!cuotas_mensuales_usuario_id_fkey(nombre)')
        .eq('parada_id', paradaId)
        .order('anio', ascending: false)
        .order('mes', ascending: false)
        .limit(50);
    return (rows as List)
        .map((r) => CuotaItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Todos los pagos de una parada, sin el límite de 50 de [cargarCuotas]
  /// — lo usa el balance detallado, que necesita el histórico completo
  /// para agrupar por mes/motivo/conductor.
  Future<List<CuotaItem>> cargarCuotasParaBalance(String paradaId) async {
    final rows = await _client
        .from('cuotas_mensuales')
        .select(
            'id, usuario_id, mes, anio, monto_total, estado, motivo, fecha_vencimiento, lote_id, metodo_pago, usuarios!cuotas_mensuales_usuario_id_fkey(nombre)')
        .eq('parada_id', paradaId)
        .order('anio', ascending: false)
        .order('mes', ascending: false);
    return (rows as List)
        .map((r) => CuotaItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Carga manual de una cuota por parte del presidente (de parada o de
  /// asociación) — ver función cuota_gestionable para quién puede
  /// hacerlo. `monto_total` se calcula acá mismo, no en la base.
  Future<void> crearCuota({
    required String organizacionId,
    required String usuarioId,
    required String paradaId,
    required int mes,
    required int anio,
    required double montoBase,
    double montoAdicional = 0,
    required DateTime fechaVencimiento,
    required DateTime fechaLimite,
    required String registradoPor,
    required String motivo,
  }) async {
    try {
      await _client.from('cuotas_mensuales').insert({
        'organizacion_id': organizacionId,
        'usuario_id': usuarioId,
        'parada_id': paradaId,
        'mes': mes,
        'anio': anio,
        'monto_base': montoBase,
        'monto_adicional': montoAdicional,
        'monto_total': montoBase + montoAdicional,
        'fecha_vencimiento': _formatoFecha(fechaVencimiento),
        'fecha_limite': _formatoFecha(fechaLimite),
        'registrado_por': registradoPor,
        'motivo': motivo,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw CuotaException('Ese conductor ya tiene un pago con ese motivo cargado para ese mes.');
      }
      throw CuotaException('No se pudo cargar el pago. Intentá de nuevo.');
    } catch (_) {
      throw CuotaException('No se pudo cargar el pago. Intentá de nuevo.');
    }
  }

  /// Cambio manual de estado (ej. registrar un pago en efectivo, o
  /// exonerar) — el presidente lo hace a mano, sin pasar por el
  /// comprobante que sube el propio conductor.
  Future<void> cambiarEstadoCuota({
    required String cuotaId,
    required String estado,
  }) async {
    try {
      await _client.from('cuotas_mensuales').update({'estado': estado}).eq('id', cuotaId);
    } catch (_) {
      throw CuotaException('No se pudo actualizar el pago. Intentá de nuevo.');
    }
  }

  String _formatoFecha(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';

  Future<List<DocumentoItem>> cargarDocumentos(String paradaId) async {
    final docsConductor = await _client
        .from('documentos_conductor')
        .select(
            'id, tipo, estado, fecha_vencimiento, archivo_url, nombre_archivo, descripcion, conductores!inner(parada_id, usuarios(nombre))')
        .eq('conductores.parada_id', paradaId);

    final docsParada = await _client
        .from('documentos_parada')
        .select('id, tipo, estado, fecha_vencimiento, archivo_url, nombre_archivo, descripcion')
        .eq('parada_id', paradaId);

    final resultado = <DocumentoItem>[];

    for (final row in docsConductor as List) {
      final map = row as Map<String, dynamic>;
      final conductor = map['conductores'] as Map<String, dynamic>?;
      final usuario = conductor?['usuarios'] as Map<String, dynamic>?;
      resultado.add(DocumentoItem(
        id: map['id'] as String,
        entidad: usuario?['nombre'] as String? ?? 'Conductor',
        tipo: map['tipo'] as String,
        estado: map['estado'] as String,
        archivoUrl: map['archivo_url'] as String,
        nombreArchivo: map['nombre_archivo'] as String?,
        descripcion: map['descripcion'] as String?,
        fechaVencimiento: map['fecha_vencimiento'] != null
            ? DateTime.parse(map['fecha_vencimiento'] as String)
            : null,
      ));
    }

    for (final row in docsParada as List) {
      final map = row as Map<String, dynamic>;
      resultado.add(DocumentoItem(
        id: map['id'] as String,
        entidad: 'Parada',
        tipo: map['tipo'] as String,
        estado: map['estado'] as String,
        archivoUrl: map['archivo_url'] as String,
        nombreArchivo: map['nombre_archivo'] as String?,
        descripcion: map['descripcion'] as String?,
        fechaVencimiento: map['fecha_vencimiento'] != null
            ? DateTime.parse(map['fecha_vencimiento'] as String)
            : null,
      ));
    }

    // Vencidos primero, después por vencer, después vigentes.
    const orden = {'vencido': 0, 'por_vencer': 1, 'vigente': 2};
    resultado.sort((a, b) =>
        (orden[a.estado] ?? 3).compareTo(orden[b.estado] ?? 3));

    return resultado;
  }

  /// El bucket "documentos" es privado — hace falta una URL firmada para
  /// poder abrir/imprimir el archivo real de un documento.
  Future<String> obtenerUrlFirmada(String path) async {
    return _client.storage.from('documentos').createSignedUrl(path, 3600);
  }

  Future<List<IncidenteItem>> cargarIncidentes(String paradaId) async {
    final rows = await _client
        .from('incidentes')
        .select('id, descripcion, tipo, estado, creado_en')
        .eq('parada_id', paradaId)
        .order('creado_en', ascending: false);
    return (rows as List)
        .map((r) => IncidenteItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Reporte manual de un incidente por parte del presidente (de parada
  /// o de asociación) — `conductorId` es opcional porque no todo
  /// incidente está atado a un conductor puntual (ej. un problema con
  /// la parada en sí).
  Future<void> crearIncidente({
    required String organizacionId,
    required String paradaId,
    String? conductorId,
    required String reportadoPor,
    required String tipo,
    required String descripcion,
  }) async {
    try {
      await _client.from('incidentes').insert({
        'organizacion_id': organizacionId,
        'parada_id': paradaId,
        'conductor_id': conductorId,
        'reportado_por': reportadoPor,
        'tipo': tipo,
        'descripcion': descripcion,
      });
    } catch (_) {
      throw IncidenteException('No se pudo reportar el incidente. Intentá de nuevo.');
    }
  }
}
