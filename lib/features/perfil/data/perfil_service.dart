import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart' show Color;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../shared/models/organizacion_branding.dart';

/// Datos necesarios para armar el carnet (perfil + vencimiento + QR).
/// El carnet muestra la organización real del socio (Traude, FETACE,
/// etc.), no la marca TapePy.
class CarnetData {
  final String usuarioId;
  final String nombre;
  final String rolLabel;
  final String? cedula;
  final String? telefono;
  final String? fotoPerfilUrl;
  final OrganizacionBranding organizacion;
  final String qrToken;
  final DateTime emision;
  final DateTime vencimiento;

  CarnetData({
    required this.usuarioId,
    required this.nombre,
    required this.rolLabel,
    required this.organizacion,
    required this.qrToken,
    required this.emision,
    required this.vencimiento,
    this.cedula,
    this.telefono,
    this.fotoPerfilUrl,
  });
}

class PerfilException implements Exception {
  final String message;
  PerfilException(this.message);
  @override
  String toString() => message;
}

/// Foto de perfil (Supabase Storage) y datos del carnet digital.
class PerfilService {
  final _client = SupabaseConfig.client;
  static const _bucket = 'avatars';

  /// Nombre, teléfono, cédula, Resolución Nº (individual, del propio
  /// socio) y correo que el usuario declara — vale para cualquier rol
  /// (conductor, presidente de parada o de asociación). No hace falta
  /// cargar la Resolución Nº al registrarse, se completa después desde
  /// acá.
  ///
  /// El correo es un caso especial: está atado a la cuenta de Supabase
  /// Auth (`auth.users.email`), no solo a la tabla `usuarios`, así que
  /// si cambió, primero se actualiza ahí (vía `auth.updateUser`, que
  /// requiere sesión activa y aplica el cambio directo -- este proyecto
  /// no depende de que lleguen correos de confirmación en ningún otro
  /// lado, ver login por cédula/reset de contraseña) y recién si eso
  /// funciona se refleja en `usuarios.email` para no desincronizar los
  /// dos lugares donde vive el correo. Pensado para casos como
  /// reemplazar un correo de prueba por el real de la persona.
  Future<void> actualizarDatosPersonales({
    required String usuarioId,
    required String nombre,
    String? telefono,
    String? cedula,
    String? resolucionIndividual,
    String? email,
  }) async {
    final emailNuevo = email?.trim();
    final emailActual = _client.auth.currentUser?.email;
    final cambioEmail =
        emailNuevo != null && emailNuevo.isNotEmpty && emailNuevo != emailActual;

    if (cambioEmail) {
      try {
        await _client.auth.updateUser(UserAttributes(email: emailNuevo));
      } catch (e) {
        throw PerfilException(_mensajeErrorEmail(e));
      }
    }

    try {
      await _client.from('usuarios').update({
        'nombre': nombre.trim(),
        'telefono': (telefono == null || telefono.trim().isEmpty) ? null : telefono.trim(),
        'cedula': (cedula == null || cedula.trim().isEmpty) ? null : cedula.trim(),
        'resolucion_individual': (resolucionIndividual == null || resolucionIndividual.trim().isEmpty)
            ? null
            : resolucionIndividual.trim(),
        if (cambioEmail) 'email': emailNuevo,
      }).eq('id', usuarioId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final detalle = e.details?.toString() ?? '';
        if (detalle.contains('resolucion_individual')) {
          throw PerfilException('Esa Resolución Nº ya está en uso por otra cuenta.');
        }
        if (detalle.contains('email')) {
          throw PerfilException('Ese correo ya está en uso por otra cuenta.');
        }
        throw PerfilException('Esa cédula ya está registrada por otra cuenta.');
      }
      throw PerfilException(cambioEmail
          ? 'El correo se actualizó, pero no se pudo guardar el resto de los cambios. Volvé a intentar.'
          : 'No se pudieron guardar los cambios. Intentá de nuevo.');
    } catch (_) {
      throw PerfilException(cambioEmail
          ? 'El correo se actualizó, pero no se pudo guardar el resto de los cambios. Volvé a intentar.'
          : 'No se pudieron guardar los cambios. Intentá de nuevo.');
    }
  }

  String _mensajeErrorEmail(Object e) {
    final texto = e.toString().toLowerCase();
    if (texto.contains('already') || texto.contains('registrad') || texto.contains('exists')) {
      return 'Ese correo ya está en uso por otra cuenta.';
    }
    if (texto.contains('invalid') || texto.contains('valid email')) {
      return 'Ese correo no es válido.';
    }
    return 'No se pudo actualizar el correo. Intentá de nuevo.';
  }

  /// Sube la foto a `avatars/{usuarioId}/foto.jpg` (siempre el mismo
  /// archivo, se reemplaza en cada subida) y actualiza
  /// `usuarios.foto_perfil_url`. Devuelve la URL pública con un parámetro
  /// de caché roto para que la UI la refresque al toque.
  Future<String> subirFotoPerfil({
    required String usuarioId,
    required Uint8List bytes,
  }) async {
    final path = '$usuarioId/foto.jpg';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    final urlBase = _client.storage.from(_bucket).getPublicUrl(path);
    final url = '$urlBase?t=${DateTime.now().millisecondsSinceEpoch}';

    await _client.from('usuarios').update({'foto_perfil_url': url}).eq('id', usuarioId);

    return url;
  }

  /// Guarda la talla de remera que el propio usuario declara (dato de
  /// perfil, no va en el carnet).
  Future<void> actualizarTallaRemera({
    required String usuarioId,
    required String tallaRemera,
  }) async {
    await _client.from('usuarios').update({'talla_remera': tallaRemera}).eq('id', usuarioId);
  }

  /// Solo la fecha de vencimiento del carnet, de lectura -- para
  /// mostrar en Datos personales sin duplicar la lógica de
  /// autogeneración de cargarDatosCarnet (que además crea el qr_token
  /// si hace falta, algo que acá no corresponde). La renovación misma
  /// es potestad de los presidentes o del dueño de plataforma, ver
  /// ParadaDetalleService.renovarCarnet -- por eso no hay
  /// actualizarVencimientoCarnet acá.
  Future<DateTime?> cargarSoloVencimientoCarnet(String usuarioId) async {
    final row = await _client
        .from('usuarios')
        .select('carnet_vencimiento')
        .eq('id', usuarioId)
        .single();
    final str = row['carnet_vencimiento'] as String?;
    return str != null ? DateTime.parse(str) : null;
  }

  /// Trae los datos para el carnet. Si el usuario todavía no tiene
  /// `qr_token` y/o `carnet_vencimiento`, los genera y guarda acá mismo
  /// (vigencia de 1 año desde hoy al generarse por primera vez;
  /// renovaciones posteriores las hace el presidente correspondiente o
  /// el dueño de plataforma desde "Vencimientos de carnet").
  Future<CarnetData> cargarDatosCarnet(String usuarioId) async {
    final row = await _client
        .from('usuarios')
        .select('id, nombre, rol, cedula, telefono, foto_perfil_url, '
            'qr_token, carnet_vencimiento, organizaciones(id, nombre, '
            'nombre_completo, tagline, logo_asset, color_primario, '
            'carnet_subtitulo, mostrar_banderas_frontera, '
            'url_verificacion_carnet)')
        .eq('id', usuarioId)
        .single();

    var qrToken = row['qr_token'] as String?;
    var vencimientoStr = row['carnet_vencimiento'] as String?;
    final actualizaciones = <String, dynamic>{};

    if (qrToken == null || qrToken.isEmpty) {
      qrToken = _generarToken();
      actualizaciones['qr_token'] = qrToken;
    }

    DateTime vencimiento;
    if (vencimientoStr == null) {
      vencimiento = DateTime.now().add(const Duration(days: 365));
      actualizaciones['carnet_vencimiento'] =
          '${vencimiento.year.toString().padLeft(4, '0')}-'
          '${vencimiento.month.toString().padLeft(2, '0')}-'
          '${vencimiento.day.toString().padLeft(2, '0')}';
    } else {
      vencimiento = DateTime.parse(vencimientoStr);
    }

    if (actualizaciones.isNotEmpty) {
      await _client.from('usuarios').update(actualizaciones).eq('id', usuarioId);
    }

    final emision = vencimiento.subtract(const Duration(days: 365));
    final organizacionMap = row['organizaciones'] as Map<String, dynamic>?;
    // Solo dueno_plataforma puede no tener organización (no debería
    // llegar a pedir un carnet, pero por las dudas no rompe).
    final organizacion = organizacionMap != null
        ? OrganizacionBranding.fromMap(organizacionMap)
        : const OrganizacionBranding(
            id: '',
            nombre: 'TapePy',
            nombreCompleto: 'TapePy',
            tagline: '',
            logoAsset: 'assets/images/tapepy_logo_blanco.png',
            colorPrimario: Color(0xFF8B0000),
          );

    return CarnetData(
      usuarioId: row['id'] as String,
      nombre: row['nombre'] as String,
      rolLabel: _labelRol(row['rol'] as String),
      cedula: row['cedula'] as String?,
      telefono: row['telefono'] as String?,
      fotoPerfilUrl: row['foto_perfil_url'] as String?,
      organizacion: organizacion,
      qrToken: qrToken,
      emision: emision,
      vencimiento: vencimiento,
    );
  }

  /// Token único para el QR del carnet. No hace falta formato UUID
  /// estricto, solo que sea impredecible — 32 caracteres hex desde un
  /// generador seguro.
  String _generarToken() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  String _labelRol(String rol) {
    const labels = {
      'dueno_plataforma': 'Dueño de plataforma',
      'superadmin': 'Superadmin',
      'presidente_asociacion': 'Presidente de Asociación',
      'presidente_parada': 'Presidente de Parada',
      'conductor': 'Conductor',
    };
    return labels[rol] ?? rol;
  }
}
