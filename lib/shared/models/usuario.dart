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
  final String? numeroSocio;
  final String? tallaRemera;
  final bool activo;
  final bool cuentaConfirmada;
  final bool enServicio;

  Usuario({
    required this.id,
    required this.organizacionId,
    required this.nombre,
    this.cedula,
    this.telefono,
    this.email,
    required this.rol,
    this.fotoPerfilUrl,
    this.numeroSocio,
    this.tallaRemera,
    required this.activo,
    this.cuentaConfirmada = true,
    this.enServicio = false,
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
      numeroSocio: numeroSocio,
      tallaRemera: tallaRemera,
      activo: activo,
      cuentaConfirmada: cuentaConfirmada,
      enServicio: enServicio,
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
      numeroSocio: map['numero_socio'] as String?,
      tallaRemera: map['talla_remera'] as String?,
      activo: map['activo'] as bool? ?? true,
      cuentaConfirmada: map['cuenta_confirmada'] as bool? ?? true,
      enServicio: map['en_servicio'] as bool? ?? false,
    );
  }
}
