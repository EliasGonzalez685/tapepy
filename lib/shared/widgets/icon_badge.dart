import 'package:flutter/material.dart';

/// Badge circular de color con un ícono adentro — el patrón visual base
/// para tarjetas de acción/estado en toda la app
/// círculos de color grandes con ícono blanco).
class IconBadge extends StatelessWidget {
  final IconData icono;
  final Color color;
  final double diametro;

  const IconBadge({
    super.key,
    required this.icono,
    required this.color,
    this.diametro = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Icon(icono, color: Colors.white, size: diametro * 0.5),
    );
  }
}
