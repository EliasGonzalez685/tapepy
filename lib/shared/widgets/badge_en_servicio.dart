import 'package:flutter/material.dart';

/// Indicador visual, de solo lectura, de si un miembro está "en
/// servicio" ahora mismo. La bandera la prende o apaga el propio
/// miembro (ver EnServicioSwitch) — acá solo se muestra a quien esté
/// viendo el listado (presidente de parada o de asociación).
class BadgeEnServicio extends StatelessWidget {
  final bool enServicio;
  const BadgeEnServicio({super.key, required this.enServicio});

  @override
  Widget build(BuildContext context) {
    final color = enServicio ? Colors.green.shade700 : Colors.grey.shade500;
    return Tooltip(
      message: enServicio ? 'En servicio' : 'Fuera de servicio',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              enServicio ? 'Activo' : 'Inactivo',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
