import 'user_role.dart';

/// Tallas de remera disponibles para completar en datos personales.
const tallasRemeraDisponibles = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];

/// Perfil de un usuario (fila de la tabla `usuarios`).
/// id coincide siempre con el id de Supabase Auth (auth.users.id).
class Usuario {
  final String id;
  final String? organizacionId; // null solo si rol == duenoPlataforma
  final String nombre;
  final String? cedula;
  final String? telefono;
  final String? email;
  final UserRole rol;
  final String? fotoPerfilUrl;
  // Resolución que habilita a ESTA persona (conductor o cualquiera de
  // los dos presidentes) — distinta de la resolución de la parada
  // (paradas.resolucion_numero). No hace falta cargarla al registrarse,
  // se completa después desde Datos personales.
  final String? resolucionIndividual;
  final String? tallaRemera;
  final bool activo;
  final bool cuentaConfirmada;
  final bool enServicio;
  // Cargo adicional, opcional y por organización (uno solo a la vez):
  // mientras es true, este usuario tiene los mismos permisos que
  // presidente_asociacion (ver auth_es_presidente_asociacion() en la
  // base), sin perder su rol normal ni sus pantallas de siempre.
  final bool esSecretario;

  Usuario({
    required this.id,
    required this.organizacionId,
    required this.nombre,
    this.cedula,
    this.telefono,
    this.email,
    required this.rol,
    this.fotoPerfilUrl,
    this.resolucionIndividual,
    this.tallaRemera,
    required this.activo,
    this.cuentaConfirmada = true,
    this.enServicio = false,
    this.esSecretario = false,
  });

  /// Clon con el/los campos indicados reemplazados. Se usa para que el
  /// dueño de plataforma pueda "pararse" sobre una organización puntual
  /// sin tocar su fila real en la base (su organizacion_id es null a
  /// propósito: no pertenece a ninguna).
  Usuario copyWith({String? organizacionId}) {
    return Usuario(
      id: id,
      organizacionId: organizacionId ?? this.organizacionId,
      nombre: nombre,
      cedula: cedula,
      telefono: telefono,
      email: email,
      rol: rol,
      fotoPerfilUrl: fotoPerfilUrl,
      resolucionIndividual: resolucionIndividual,
      tallaRemera: tallaRemera,
      activo: activo,
      cuentaConfirmada: cuentaConfirmada,
      enServicio: enServicio,
      esSecretario: esSecretario,
    );
  }

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'] as String,
      organizacionId: map['organizacion_id'] as String?,
      nombre: map['nombre'] as String,
      cedula: map['cedula'] as String?,
      telefono: map['telefono'] as String?,
      email: map['email'] as String?,
      rol: UserRole.fromString(map['rol'] as String),
      fotoPerfilUrl: map['foto_perfil_url'] as String?,
      resolucionIndividual: map['resolucion_individual'] as String?,
      tallaRemera: map['talla_remera'] as String?,
      activo: map['activo'] as bool? ?? true,
      cuentaConfirmada: map['cuenta_confirmada'] as bool? ?? true,
      enServicio: map['en_servicio'] as bool? ?? false,
      esSecretario: map['es_secretario'] as bool? ?? false,
    );
  }
}
