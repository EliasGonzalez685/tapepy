import '../../../core/config/supabase_config.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/models/usuario.dart';

/// Tope de caracteres por mensaje — reforzado también en la base (ver
/// constraint mensajes_contenido_max_200) para que no se pueda saltear
/// llamando a la API directo.
const mensajeMaxCaracteres = 200;

class MensajeException implements Exception {
  final String message;
  MensajeException(this.message);
  @override
  String toString() => message;
}

/// Un mensaje dentro de un hilo ya abierto — acá lo único que importa
/// es si lo mandé yo o el otro, para dibujar la burbuja de un lado o
/// del otro.
class MensajeHilo {
  final String id;
  final String contenido;
  final bool esMio;
  final bool leido;
  final DateTime enviadoEn;

  MensajeHilo({
    required this.id,
    required this.contenido,
    required this.esMio,
    required this.leido,
    required this.enviadoEn,
  });

  factory MensajeHilo.fromMap(Map<String, dynamic> map, {required String usuarioId}) {
    return MensajeHilo(
      id: map['id'] as String,
      contenido: map['contenido'] as String,
      esMio: map['de'] as String == usuarioId,
      leido: map['leido'] as bool? ?? false,
      enviadoEn: DateTime.parse(map['enviado_en'] as String),
    );
  }
}

/// Una fila en la lista de conversaciones: con quién es, cómo quedó el
/// último mensaje y cuántos sin leer hay de esa persona.
class ConversacionResumen {
  final String otroUsuarioId;
  final String otroNombre;
  final String otroRolLabel;
  final String ultimoMensaje;
  final DateTime ultimoEnviadoEn;
  final bool ultimoEsMio;
  final int noLeidos;

  ConversacionResumen({
    required this.otroUsuarioId,
    required this.otroNombre,
    required this.otroRolLabel,
    required this.ultimoMensaje,
    required this.ultimoEnviadoEn,
    required this.ultimoEsMio,
    required this.noLeidos,
  });
}

/// A quién puede escribirle el usuario logueado — ver
/// [MensajeriaService.cargarDestinatariosPosibles] para las reglas.
class DestinatarioItem {
  final String usuarioId;
  final String nombre;
  final String rolLabel;

  DestinatarioItem({
    required this.usuarioId,
    required this.nombre,
    required this.rolLabel,
  });
}

/// Mensajería interna entre miembros de una misma organización.
/// `mensajes` tiene dos FK a `usuarios` (de/para), por eso el embed de
/// lectura necesita el hint `!de` para desambiguar cuál relación traer.
///
/// Quién le puede escribir a quién (reforzado también por RLS, ver
/// función mensajes_destinatario_valido):
/// - conductor: al presidente de SU parada, o al presidente de asociación.
///   No a conductores ni presidentes de otras paradas.
/// - presidente de parada: a los conductores de SU parada, a los demás
///   presidentes de parada de la organización, y al presidente de
///   asociación. No a conductores de otras paradas.
/// - presidente de asociación: a cualquier miembro de la organización.
/// - dueño de plataforma: a nadie — esto es trabajo interno de cada
///   asociación, no algo que le corresponda a la plataforma.
class MensajeriaService {
  final _client = SupabaseConfig.client;

  Future<int> contarNoLeidos(String usuarioId) async {
    final rows = await _client
        .from('mensajes')
        .select('id')
        .eq('para', usuarioId)
        .eq('leido', false);
    return (rows as List).length;
  }

  /// Todas las conversaciones del usuario, una fila por interlocutor
  /// (agrupado en el cliente — el volumen de mensajes de una asociación
  /// es chico, no hace falta agregarlo en SQL). RLS ya solo devuelve los
  /// mensajes donde el usuario es de o para, así que no hace falta
  /// filtrar nada más acá.
  Future<List<ConversacionResumen>> cargarConversaciones(String usuarioId) async {
    final rows = await _client
        .from('mensajes')
        .select(
            'id, de, para, contenido, leido, enviado_en, remitente:usuarios!de(id, nombre, rol), destinatario:usuarios!para(id, nombre, rol)')
        .or('de.eq.$usuarioId,para.eq.$usuarioId')
        .order('enviado_en', ascending: false);

    final porInterlocutor = <String, ConversacionResumen>{};
    for (final r in rows as List) {
      final map = r as Map<String, dynamic>;
      final deId = map['de'] as String;
      final esMio = deId == usuarioId;
      final otro = (esMio ? map['destinatario'] : map['remitente']) as Map<String, dynamic>;
      final otroId = otro['id'] as String;

      if (!porInterlocutor.containsKey(otroId)) {
        porInterlocutor[otroId] = ConversacionResumen(
          otroUsuarioId: otroId,
          otroNombre: otro['nombre'] as String? ?? 'Desconocido',
          otroRolLabel: UserRole.fromString(otro['rol'] as String).label,
          ultimoMensaje: map['contenido'] as String,
          ultimoEnviadoEn: DateTime.parse(map['enviado_en'] as String),
          ultimoEsMio: esMio,
          noLeidos: 0,
        );
      }
      if (!esMio && map['leido'] == false) {
        final actual = porInterlocutor[otroId]!;
        porInterlocutor[otroId] = ConversacionResumen(
          otroUsuarioId: actual.otroUsuarioId,
          otroNombre: actual.otroNombre,
          otroRolLabel: actual.otroRolLabel,
          ultimoMensaje: actual.ultimoMensaje,
          ultimoEnviadoEn: actual.ultimoEnviadoEn,
          ultimoEsMio: actual.ultimoEsMio,
          noLeidos: actual.noLeidos + 1,
        );
      }
    }
    final lista = porInterlocutor.values.toList()
      ..sort((a, b) => b.ultimoEnviadoEn.compareTo(a.ultimoEnviadoEn));
    return lista;
  }

  /// El hilo completo entre el usuario logueado y otra persona, en
  /// orden cronológico (más viejo primero, como cualquier chat).
  Future<List<MensajeHilo>> cargarConversacion({
    required String usuarioId,
    required String otroUsuarioId,
  }) async {
    final rows = await _client
        .from('mensajes')
        .select('id, de, contenido, leido, enviado_en')
        .or('and(de.eq.$usuarioId,para.eq.$otroUsuarioId),and(de.eq.$otroUsuarioId,para.eq.$usuarioId)')
        .order('enviado_en');
    return (rows as List)
        .map((r) => MensajeHilo.fromMap(r as Map<String, dynamic>, usuarioId: usuarioId))
        .toList();
  }

  /// Marca como leídos todos los mensajes que la otra persona me mandó
  /// a mí en esta conversación — se llama al abrir el hilo.
  Future<void> marcarConversacionLeida({
    required String usuarioId,
    required String otroUsuarioId,
  }) async {
    await _client
        .from('mensajes')
        .update({'leido': true})
        .eq('de', otroUsuarioId)
        .eq('para', usuarioId)
        .eq('leido', false);
  }

  Future<void> enviarMensaje({
    required String organizacionId,
    required String de,
    required String para,
    required String contenido,
  }) async {
    final texto = contenido.trim();
    if (texto.isEmpty) {
      throw MensajeException('Escribí un mensaje antes de enviar.');
    }
    if (texto.length > mensajeMaxCaracteres) {
      throw MensajeException('El mensaje no puede superar los $mensajeMaxCaracteres caracteres.');
    }
    try {
      await _client.from('mensajes').insert({
        'organizacion_id': organizacionId,
        'de': de,
        'para': para,
        'contenido': texto,
      });
    } catch (_) {
      throw MensajeException('No se pudo enviar el mensaje. Intentá de nuevo.');
    }
  }

  /// Lista de posibles destinatarios según el rol del usuario logueado.
  Future<List<DestinatarioItem>> cargarDestinatariosPosibles(Usuario usuario) async {
    switch (usuario.rol) {
      case UserRole.conductor:
        return _destinatariosDeConductor(usuario);
      case UserRole.presidenteParada:
        return _destinatariosDePresidenteParada(usuario);
      case UserRole.presidenteAsociacion:
        return _destinatariosDeOrganizacion(usuario);
      case UserRole.duenoPlataforma:
      case UserRole.superadmin:
        return [];
    }
  }

  Future<List<DestinatarioItem>> _destinatariosDeConductor(Usuario usuario) async {
    final destinatarios = <DestinatarioItem>[];

    final conductorRow = await _client
        .from('conductores')
        .select('parada_id')
        .eq('usuario_id', usuario.id)
        .maybeSingle();
    final paradaId = conductorRow?['parada_id'] as String?;

    if (paradaId != null) {
      final paradaRow = await _client
          .from('paradas')
          .select('usuarios(id, nombre)')
          .eq('id', paradaId)
          .maybeSingle();
      final presidente = paradaRow?['usuarios'] as Map<String, dynamic>?;
      if (presidente != null) {
        destinatarios.add(DestinatarioItem(
          usuarioId: presidente['id'] as String,
          nombre: presidente['nombre'] as String,
          rolLabel: 'Presidente de Parada',
        ));
      }
    }

    final presidenteAsociacion = await _cargarPresidenteAsociacion(usuario.organizacionId);
    if (presidenteAsociacion != null) destinatarios.add(presidenteAsociacion);

    return destinatarios;
  }

  Future<List<DestinatarioItem>> _destinatariosDePresidenteParada(Usuario usuario) async {
    final destinatarios = <DestinatarioItem>[];

    final paradaRow = await _client
        .from('paradas')
        .select('id')
        .eq('presidente_id', usuario.id)
        .maybeSingle();
    final paradaId = paradaRow?['id'] as String?;

    if (paradaId != null) {
      final rows = await _client
          .from('conductores')
          .select('usuarios!inner(id, nombre, cuenta_confirmada)')
          .eq('parada_id', paradaId)
          .eq('usuarios.cuenta_confirmada', true);
      for (final r in rows as List) {
        final u = (r as Map<String, dynamic>)['usuarios'] as Map<String, dynamic>;
        final id = u['id'] as String;
        if (id == usuario.id) continue; // el propio presidente también figura como conductor
        destinatarios.add(DestinatarioItem(
          usuarioId: id,
          nombre: u['nombre'] as String,
          rolLabel: 'Conductor',
        ));
      }
    }

    final otrosPresidentes = await _otrosPresidentesDeParada(
      organizacionId: usuario.organizacionId,
      propiaParadaId: paradaId,
    );
    destinatarios.addAll(otrosPresidentes);

    final presidenteAsociacion = await _cargarPresidenteAsociacion(usuario.organizacionId);
    if (presidenteAsociacion != null) destinatarios.add(presidenteAsociacion);

    destinatarios.sort((a, b) => a.nombre.compareTo(b.nombre));
    return destinatarios;
  }

  /// Presidentes de OTRAS paradas de la misma organización (para que un
  /// presidente de parada pueda escribirse con sus pares) — excluye la
  /// propia parada y las que todavía no tienen presidente asignado.
  Future<List<DestinatarioItem>> _otrosPresidentesDeParada({
    required String? organizacionId,
    required String? propiaParadaId,
  }) async {
    if (organizacionId == null) return [];
    var query = _client
        .from('paradas')
        .select('id, presidente_id, usuarios(id, nombre)')
        .eq('organizacion_id', organizacionId)
        .not('presidente_id', 'is', null);
    if (propiaParadaId != null) {
      query = query.neq('id', propiaParadaId);
    }
    final rows = await query;
    final destinatarios = <DestinatarioItem>[];
    for (final r in rows as List) {
      final map = r as Map<String, dynamic>;
      final presidente = map['usuarios'] as Map<String, dynamic>?;
      if (presidente == null) continue;
      destinatarios.add(DestinatarioItem(
        usuarioId: presidente['id'] as String,
        nombre: presidente['nombre'] as String,
        rolLabel: 'Presidente de Parada',
      ));
    }
    return destinatarios;
  }

  Future<List<DestinatarioItem>> _destinatariosDeOrganizacion(Usuario usuario) async {
    final organizacionId = usuario.organizacionId;
    if (organizacionId == null) return [];
    final rows = await _client
        .from('usuarios')
        .select('id, nombre, rol')
        .eq('organizacion_id', organizacionId)
        .eq('cuenta_confirmada', true)
        .neq('id', usuario.id)
        .order('nombre');
    return (rows as List).map((r) {
      final map = r as Map<String, dynamic>;
      return DestinatarioItem(
        usuarioId: map['id'] as String,
        nombre: map['nombre'] as String,
        rolLabel: UserRole.fromString(map['rol'] as String).label,
      );
    }).toList();
  }

  Future<DestinatarioItem?> _cargarPresidenteAsociacion(String? organizacionId) async {
    if (organizacionId == null) return null;
    final row = await _client
        .from('usuarios')
        .select('id, nombre')
        .eq('organizacion_id', organizacionId)
        .eq('rol', 'presidente_asociacion')
        .maybeSingle();
    if (row == null) return null;
    return DestinatarioItem(
      usuarioId: row['id'] as String,
      nombre: row['nombre'] as String,
      rolLabel: 'Presidente de Asociación',
    );
  }
}
