import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';

/// Datos necesarios para armar el carnet (perfil + vencimiento + QR).
/// El carnet muestra la organización (Traude), no la marca TapePy.
class CarnetData {
  final String usuarioId;
  final String nombre;
  final String rolLabel;
  final String? cedula;
  final String? telefono;
  final String? numeroSocio;
  final String? fotoPerfilUrl;
  final String organizacionNombre;
  final String qrToken;
  final DateTime emision;
  final DateTime vencimiento;

  CarnetData({
    required this.usuarioId,
    required this.nombre,
    required this.rolLabel,
    required this.organizacionNombre,
    required this.qrToken,
    required this.emision,
    required this.vencimiento,
    this.cedula,
    this.telefono,
    this.numeroSocio,
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

  /// Nombre, teléfono, cédula y N° de socio que el propio usuario
  /// declara — vale para cualquier rol (conductor, presidente de
  /// parada o de asociación). Email queda afuera a propósito: está
  /// atado a la cuenta de Supabase Auth y cambiarlo acá lo desincroniza.
  Future<void> actualizarDatosPersonales({
    required String usuarioId,
    required String nombre,
    String? telefono,
    String? cedula,
    String? numeroSocio,
  }) async {
    try {
      await _client.from('usuarios').update({
        'nombre': nombre.trim(),
        'telefono': (telefono == null || telefono.trim().isEmpty) ? null : telefono.trim(),
        'cedula': (cedula == null || cedula.trim().isEmpty) ? null : cedula.trim(),
        'numero_socio':
            (numeroSocio == null || numeroSocio.trim().isEmpty) ? null : numeroSocio.trim(),
      }).eq('id', usuarioId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final detalle = e.details?.toString() ?? '';
        if (detalle.contains('numero_socio')) {
          throw PerfilException('Ese N° de socio ya está en uso por otra cuenta.');
        }
        throw PerfilException('Esa cédula ya está registrada por otra cuenta.');
      }
      throw PerfilException('No se pudieron guardar los cambios. Intentá de nuevo.');
    } catch (_) {
      throw PerfilException('No se pudieron guardar los cambios. Intentá de nuevo.');
    }
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

  /// Trae los datos para el carnet. Si el usuario todavía no tiene
  /// `qr_token` y/o `carnet_vencimiento`, los genera y guarda acá mismo
  /// (vigencia de 1 año desde hoy — regla nombrada por Elias, sin
  /// automatización de renovación todavía).
  Future<CarnetData> cargarDatosCarnet(String usuarioId) async {
    final row = await _client
        .from('usuarios')
        .select('id, nombre, rol, numero_socio, cedula, telefono, foto_perfil_url, '
            'qr_token, carnet_vencimiento, organizaciones(nombre)')
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
    final organizacion = row['organizaciones'] as Map<String, dynamic>?;

    return CarnetData(
      usuarioId: row['id'] as String,
      nombre: row['nombre'] as String,
      rolLabel: _labelRol(row['rol'] as String),
      cedula: row['cedula'] as String?,
      telefono: row['telefono'] as String?,
      numeroSocio: row['numero_socio'] as String?,
      fotoPerfilUrl: row['foto_perfil_url'] as String?,
      organizacionNombre: organizacion?['nombre'] as String? ?? 'Traude',
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
