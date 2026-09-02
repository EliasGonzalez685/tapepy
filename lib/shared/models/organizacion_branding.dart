import 'package:flutter/material.dart';

/// Identidad visual de una organización cliente de TapePy (nombre,
/// logo, color institucional). Se lee de la tabla `organizaciones` —
/// cada organización (Traude, FETACE, y las que se sumen después)
/// tiene la suya, así ninguna pantalla queda con el nombre de otra
/// organización escrito fijo.
class OrganizacionBranding {
  final String id;
  final String nombre;
  final String nombreCompleto;
  final String tagline;
  final String logoAsset;
  final Color colorPrimario;
  // Subtítulo chico opcional para el dorso del carnet (rubro de
  // servicios) — null si la organización no cargó uno.
  final String? carnetSubtitulo;
  // Si corresponde mostrar las banderitas de países frontera en el
  // dorso del carnet (tiene sentido para asociaciones que cruzan
  // frontera, no para las que operan en una sola ciudad).
  final bool mostrarBanderasFrontera;
  // Línea legal (reconocimiento/personería jurídica) y teléfono para el
  // membrete de los listados imprimibles — null si la organización no
  // los cargó (no se inventa nada, simplemente no sale esa línea).
  final String? membreteLegal;
  final String? telefonoMembrete;

  const OrganizacionBranding({
    required this.id,
    required this.nombre,
    required this.nombreCompleto,
    required this.tagline,
    required this.logoAsset,
    required this.colorPrimario,
    this.carnetSubtitulo,
    this.mostrarBanderasFrontera = false,
    this.membreteLegal,
    this.telefonoMembrete,
  });

  factory OrganizacionBranding.fromMap(Map<String, dynamic> map) {
    return OrganizacionBranding(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      nombreCompleto: map['nombre_completo'] as String,
      tagline: map['tagline'] as String,
      logoAsset: map['logo_asset'] as String,
      colorPrimario: _colorDesdeHex(map['color_primario'] as String),
      carnetSubtitulo: map['carnet_subtitulo'] as String?,
      mostrarBanderasFrontera: map['mostrar_banderas_frontera'] as bool? ?? false,
      membreteLegal: map['membrete_legal'] as String?,
      telefonoMembrete: map['telefono_membrete'] as String?,
    );
  }

  static Color _colorDesdeHex(String hex) {
    final limpio = hex.replaceFirst('#', '');
    return Color(int.parse('FF$limpio', radix: 16));
  }
}
