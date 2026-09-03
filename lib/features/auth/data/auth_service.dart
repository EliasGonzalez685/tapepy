import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../shared/models/usuario.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Login + lectura del perfil (tabla `usuarios`) del usuario autenticado.
class AuthService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Inicia sesión y devuelve el perfil completo (con rol y organización).
  /// [identificador] puede ser el email o la cédula — si no tiene "@" se
  /// resuelve a email primero (ver [_resolverEmail]), porque Supabase
  /// Auth siempre loguea contra un email.
  ///
  /// Bloqueo por intentos fallidos (pedido de Elias, 2026-08-20): a los
  /// 5 intentos seguidos con contraseña incorrecta la cuenta queda
  /// bloqueada -- no se autodesbloquea sola con el tiempo, solo el
  /// dueño de plataforma puede levantarla desde su panel. Todo el
  /// conteo vive en el backend (columnas + funciones en `usuarios`),
  /// acá solo se consulta/reporta.
  ///
  /// Tira [AuthException] con un mensaje entendible si algo falla.
  Future<Usuario> signIn({
    required String identificador,
    required String password,
  }) async {
    try {
      final email = await _resolverEmail(identificador.trim());

      final bloqueado = await _client.rpc(
        'login_verificar_bloqueo',
        params: {'p_email': email},
      ) as bool? ??
          false;
      if (bloqueado) {
        throw AuthException(
          'Esta cuenta quedó bloqueada por varios intentos fallidos. '
          'Solo el dueño de la plataforma puede desbloquearla.',
        );
      }

      final AuthResponse authResponse;
      try {
        authResponse = await _client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } on AuthApiException catch (e) {
        if (e.code == 'invalid_credentials') {
          await _client.rpc('login_registrar_fallo', params: {'p_email': email});
        }
        rethrow;
      }

      // Login correcto: resetear el contador de intentos fallidos.
      await _client.rpc('login_registrar_exito');

      final user = authResponse.user;
      final userId = user?.id;
      if (userId == null) {
        throw AuthException('No se pudo iniciar sesión. Intentá de nuevo.');
      }

      var filas = await _client.from('usuarios').select().eq('id', userId).limit(1);
      var lista = filas as List;

      if (lista.isEmpty) {
        // Se registró pero (por confirmación de email u otro corte) el
        // alta en usuarios/conductores no se llegó a completar en su
        // momento. Si guardamos los datos pendientes al registrarse,
        // la completamos recién ahora.
        final pendiente =
            user!.userMetadata?['registro_pendiente'] as Map<String, dynamic>?;
        if (pendiente == null) {
          await _client.auth.signOut();
          throw AuthException(
            'No se encontró tu perfil de usuario. Contactá al administrador.',
          );
        }
        await _completarRegistroPendiente(pendiente);
        filas = await _client.from('usuarios').select().eq('id', userId).limit(1);
        lista = filas as List;
        if (lista.isEmpty) {
          throw AuthException('No se pudo completar tu registro. Intentá de nuevo.');
        }
      }

      final usuario = Usuario.fromMap(lista.first as Map<String, dynamic>);

      if (!usuario.cuentaConfirmada) {
        await _client.auth.signOut();
        throw AuthException(
          'Tu registro todavía no fue aprobado por las autoridades de tu asociación. '
          'Te vamos a avisar cuando puedas ingresar.',
        );
      }

      if (!usuario.activo) {
        await _client.auth.signOut();
        throw AuthException(
          'Tu cuenta está desactivada. Contactá al presidente de tu asociación.',
        );
      }

      return usuario;
    } on AuthException {
      rethrow;
    } on AuthApiException catch (e) {
      throw AuthException(_mensajeLegible(e));
    } on PostgrestException {
      throw AuthException(
        'No se encontró tu perfil de usuario. Contactá al administrador.',
      );
    } catch (e) {
      throw AuthException('Error inesperado. Revisá tu conexión e intentá de nuevo.');
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Si ya parece un email, lo usa tal cual. Si no, lo trata como
  /// cédula y pide el email asociado vía RPC (la tabla `usuarios` no
  /// está abierta a antes-de-loguearse, así que no se puede resolver
  /// con un select directo).
  Future<String> _resolverEmail(String identificador) async {
    if (identificador.contains('@')) return identificador;
    final email = await _client.rpc(
      'resolver_email_por_cedula',
      params: {'p_cedula': identificador},
    ) as String?;
    if (email == null || email.isEmpty) {
      throw AuthException('No encontramos ninguna cuenta con esa cédula.');
    }
    return email;
  }

  /// Corre la función `completar_registro_conductor` con los datos que
  /// se guardaron como metadata al momento del alta (ver
  /// RegistroService.registrarConductor). Deja usuarios + conductores
  /// creados en una sola transacción.
  Future<void> _completarRegistroPendiente(Map<String, dynamic> datos) async {
    final organizacionId = datos['organizacion_id'] as String?;
    final paradaId = datos['parada_id'] as String?;
    final nombre = datos['nombre'] as String?;
    if (organizacionId == null || nombre == null) {
      throw AuthException(
        'Faltan datos para completar tu registro. Contactá al administrador.',
      );
    }
    await _client.rpc('completar_registro_conductor', params: {
      'p_organizacion_id': organizacionId,
      'p_parada_id': paradaId,
      'p_nombre': nombre,
      'p_cedula': datos['cedula'],
      'p_telefono': datos['telefono'],
      'p_email': datos['email'],
    });
  }

  String _mensajeLegible(AuthApiException e) {
    switch (e.code) {
      case 'invalid_credentials':
        return 'Cédula/email o contraseña incorrectos.';
      case 'email_not_confirmed':
        // No usamos confirmación por email en ningún lado — si esto
        // aparece es porque la cuenta todavía espera la aprobación de
        // alguna autoridad de la asociación (presidente de parada, de
        // asociación o el dueño de plataforma), no un correo.
        return 'Tu registro todavía no fue aprobado por las autoridades de tu asociación. '
            'Te vamos a avisar cuando puedas ingresar.';
      default:
        return e.message;
    }
  }
}
