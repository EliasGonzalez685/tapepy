import 'package:flutter/material.dart';

/// Rubro de servicio de una organización. Se usa en la pantalla previa
/// a "Elegí tu organización": primero el usuario elige el rubro
/// (Transporte Alternativo / Taxi / Mototaxi) y recién ahí ve el
/// listado de organizaciones de ese rubro, en vez de ver todas las
/// organizaciones de la plataforma juntas desde el arranque.
///
/// El valor de cada opción (`valorDb`) tiene que coincidir con los
/// valores permitidos por el check constraint de
/// `organizaciones.tipo` (ver migración 0049).
enum TipoOrganizacion {
  transporteAlternativo(
    valorDb: 'transporte_alternativo',
    label: 'Transporte Alternativo',
    descripcion: 'Asociaciones de transporte alternativo entre ciudades.',
    icono: Icons.directions_bus_filled_outlined,
  ),
  taxi(
    valorDb: 'taxi',
    label: 'Taxi',
    descripcion: 'Federaciones y asociaciones de taxis.',
    icono: Icons.local_taxi_outlined,
  ),
  mototaxi(
    valorDb: 'mototaxi',
    label: 'Mototaxi',
    descripcion: 'Asociaciones de mototaxis.',
    icono: Icons.two_wheeler_outlined,
  );

  final String valorDb;
  final String label;
  final String descripcion;
  final IconData icono;

  const TipoOrganizacion({
    required this.valorDb,
    required this.label,
    required this.descripcion,
    required this.icono,
  });

  /// Busca el enum a partir del valor guardado en la base de datos.
  /// Devuelve null si no coincide con ninguno (organización sin
  /// clasificar todavía, o valor viejo/desconocido).
  static TipoOrganizacion? desdeValorDb(String? valor) {
    if (valor == null) return null;
    for (final tipo in TipoOrganizacion.values) {
      if (tipo.valorDb == valor) return tipo;
    }
    return null;
  }
}
