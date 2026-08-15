import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../shared/models/usuario.dart';

class RegistroException implements Exception {
  final String message;
  RegistroException(this.message);
  @override
  String toString() => message;
}

class OrganizacionOpcion {
  final String id;
  final String nombre;
  OrganizacionOpcion({required this.id, required this.nombre});
}

class ParadaOpcion {
  final String id;
  final String nombre;
  ParadaOpcion({required this.id, required this.nombre});
}

/// Alta pública de un nuevo miembro. Todos se registran así con rol
/// 'conductor' — conductores y también quien más adelante el
/// presidente de asociación ascienda a presidente de parada (esa
/// promoción es otra pantalla, no parte de este flujo). El presidente
/// de asociación es la única cuenta que se sigue creando a mano.
class RegistroService {
  final _client = SupabaseConfig.client;

  Future<List<OrganizacionOpcion>> cargarOrganizaciones() async {
    final rows = await _client
        .from('organizaciones')
        .select('id, nombre')
        .eq('activo', true)
        .order('nombre');
    return (rows as List)
        .map((r) => OrganizacionOpcion(
              id: r['id'] as String,
              nombre: r['nombre'] as String,
            ))
        .toList();
  }

  Future<List<ParadaOpcion>> cargarParadas(String organizacionId) async {
    final rows = await _client
        .from('paradas')
        .select('id, nombre')
        .eq('organizacion_id', organizacionId)
        .order('nombre');
    return (rows as List)
        .map((r) => ParadaOpcion(id: r['id'] as String, nombre: r['nombre'] as String))
        .toList();
  }

  /// Crea la cuenta (Supabase Auth) y, si queda con sesión activa al
  /// toque (proyecto sin confirmación de email obligatoria), completa
  /// el alta ahí mismo devolviendo el [Usuario] ya listo para navegar a
  /// su panel. Si hace falta confirmar el email primero, devuelve
  /// `null` — los datos quedan guardados en el metadata de la cuenta y
  /// se completan solos la primera vez que inicie sesión (ver
  /// AuthService.signIn).
  Future<Usuario?> registrarConductor({
    required String nombre,
    required String cedula,
    required String telefono,
    required String email,
    required String password,
    required String organizacionId,
    required String paradaId,
  }) async {
    try {
      final datosPendientes = {
        'nombre': nombre,
        'cedula': cedula,
        'telefono': telefono,
        'email': email,
        'organizacion_id': organizacionId,
        'parada_id': paradaId,
      };

      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'registro_pendiente': datosPendientes},
      );

      final userId = response.user?.id;
      if (response.session == null || userId == null) {
        // Confirmación de email requerida: todavía no hay sesión activa
        // para poder insertar usuarios/conductores.
        return null;
      }

      await _client.rpc('completar_registro_conductor', params: {
        'p_organizacion_id': organizacionId,
        'p_parada_id': paradaId,
        'p_nombre': nombre,
        'p_cedula': cedula,
        'p_telefono': telefono,
        'p_email': email,
      });

      final perfil = await _client.from('usuarios').select().eq('id', userId).single();
      return Usuario.fromMap(perfil);
    } on AuthApiException catch (e) {
      throw RegistroException(_mensajeLegible(e));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw RegistroException(
          'Ese email o esa cédula ya están registrados.',
        );
      }
      throw RegistroException('No se pudo completar el registro. Intentá de nuevo.');
    } catch (_) {
      throw RegistroException('Error inesperado. Revisá tu conexión e intentá de nuevo.');
    }
  }

  String _mensajeLegible(AuthApiException e) {
    switch (e.code) {
      case 'user_already_exists':
        return 'Ya existe una cuenta con ese email.';
      case 'weak_password':
        return 'La contraseña es muy débil. Usá al menos 6 caracteres.';
      default:
        return e.message;
    }
  }
}
