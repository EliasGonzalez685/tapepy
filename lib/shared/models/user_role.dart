/// Roles definidos en el modelo de datos de TapePy.
/// (Válidos dentro de cada organización/cliente, ej. Traude.)
enum UserRole {
  duenoPlataforma,
  superadmin,
  presidenteAsociacion,
  presidenteParada,
  conductor;

  static UserRole fromString(String value) {
    switch (value) {
      case 'dueno_plataforma':
        return UserRole.duenoPlataforma;
      case 'superadmin':
        return UserRole.superadmin;
      case 'presidente_asociacion':
        return UserRole.presidenteAsociacion;
      case 'presidente_parada':
        return UserRole.presidenteParada;
      case 'conductor':
        return UserRole.conductor;
      default:
        throw ArgumentError('Rol desconocido: $value');
    }
  }
}

extension UserRoleUi on UserRole {
  String get label {
    switch (this) {
      case UserRole.duenoPlataforma:
        return 'Dueño de plataforma';
      case UserRole.superadmin:
        return 'Superadmin';
      case UserRole.presidenteAsociacion:
        return 'Presidente de Asociación';
      case UserRole.presidenteParada:
        return 'Presidente de Parada';
      case UserRole.conductor:
        return 'Conductor';
    }
  }
}
