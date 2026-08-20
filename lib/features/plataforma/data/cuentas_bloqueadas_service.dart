import 'package:intl/intl.dart';
import '../../../core/config/supabase_config.dart';
import '../../../shared/models/user_role.dart';

/// Una cuenta bloqueada por intentos fallidos de login. El bloqueo en sí
/// (columna `bloqueado` en `usuarios`) solo lo pone/saca el dueño de
/// plataforma -- ver la migración `bloqueo_login_intentos_fallidos` y el
/// trigger `usuarios_proteger_columnas_sensibles`, que revierte esa
/// columna si la toca cualquier otro rol.
class CuentaBloqueadaItem {
  final String id;
  final String nombre;
  final String? cedula;
  final String email;
  final UserRole rol;
  final String? organizacionNombre;
  final int intentosFallidos;
  final DateTime? bloqueadoEn;

  CuentaBloqueadaItem({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.intentosFallidos,
    this.cedula,
    this.organizacionNombre,
    this.bloqueadoEn,
  });

  factory CuentaBloqueadaItem.fromMap(Map<String, dynamic> map) {
    final organizacion = map['organizaciones'] as Map<String, dynamic>?;
    final bloqueadoEn = map['bloqueado_en'] as String?;
    return CuentaBloqueadaItem(
      id: map['id'] as String,
      nombre: map['nombre'] as String? ?? 'Sin nombre',
      cedula: map['cedula'] as String?,
      email: map['email'] as String? ?? '',
      rol: UserRole.fromString(map['rol'] as String),
      organizacionNombre: organizacion?['nombre'] as String?,
      intentosFallidos: map['intentos_fallidos'] as int? ?? 0,
      bloqueadoEn: bloqueadoEn != null ? DateTime.parse(bloqueadoEn) : null,
    );
  }

  String get bloqueadoEnTexto =>
      bloqueadoEn != null ? DateFormat('dd/MM/yyyy HH:mm').format(bloqueadoEn!) : '—';
}

class CuentasBloqueadasService {
  final _client = SupabaseConfig.client;

  /// Solo el dueño de plataforma llega a ver algo acá -- por RLS
  /// (org_isolation_select), cualquier otro rol solo vería las cuentas
  /// de su propia organización, pero esta pantalla ni se le muestra.
  Future<List<CuentaBloqueadaItem>> cargarBloqueadas() async {
    final rows = await _client
        .from('usuarios')
        .select('id, nombre, cedula, email, rol, intentos_fallidos, bloqueado_en, organizaciones(nombre)')
        .eq('bloqueado', true)
        .order('bloqueado_en', ascending: false);
    return (rows as List).map((r) => CuentaBloqueadaItem.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Desbloquea la cuenta y reinicia el contador. El trigger de
  /// blindaje solo deja pasar este UPDATE si quien llama es
  /// efectivamente el dueño de plataforma (si no, la fila queda igual
  /// y esta pantalla ni siquiera es alcanzable para otro rol).
  Future<void> desbloquear(String usuarioId) async {
    await _client.from('usuarios').update({
      'bloqueado': false,
      'intentos_fallidos': 0,
      'bloqueado_en': null,
    }).eq('id', usuarioId);
  }
}
