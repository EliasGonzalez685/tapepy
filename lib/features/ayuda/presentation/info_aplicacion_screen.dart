import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Ficha simple con qué es TapePy — primer ítem del menú "Ayuda y
/// comentarios", igual para cualquier rol.
class InfoAplicacionScreen extends StatelessWidget {
  const InfoAplicacionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Info de la aplicación')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppTheme.rojoInstitucional,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: Text('TP',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 30)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text('TapePy', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Versión 0.1.0',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 28),
          const Text(
            'TapePy es una plataforma de gestión para asociaciones de transporte. '
            'Permite registrar socios y sus vehículos, cargar y verificar '
            'documentación, generar carnets digitales y constancias, administrar '
            'el cobro de cuotas, comunicarse internamente y generar listados '
            'oficiales.',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Traude es la primera organización que usa TapePy.',
            style: TextStyle(height: 1.5, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}
