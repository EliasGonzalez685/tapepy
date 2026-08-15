import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data/legal_content.dart';

/// Muestra los Términos de Uso y la Política de Privacidad dentro de la
/// app (mismo contenido que los documentos Word en docs/legal/).
class CondicionesPrivacidadScreen extends StatelessWidget {
  const CondicionesPrivacidadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Condiciones y Privacidad'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Términos de Uso'),
              Tab(text: 'Política de Privacidad'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ListaSecciones(secciones: terminosDeUso),
            _ListaSecciones(secciones: politicaDePrivacidad),
          ],
        ),
      ),
    );
  }
}

class _ListaSecciones extends StatelessWidget {
  final List<SeccionLegal> secciones;
  const _ListaSecciones({required this.secciones});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(legalVersion,
            style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13)),
        const SizedBox(height: 16),
        for (final seccion in secciones) ...[
          Text(seccion.titulo,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.rojoInstitucional)),
          const SizedBox(height: 8),
          for (final parrafo in seccion.parrafos) ...[
            Text(parrafo, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
