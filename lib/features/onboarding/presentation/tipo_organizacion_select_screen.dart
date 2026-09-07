import 'package:flutter/material.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/models/tipo_organizacion.dart';

/// Primera pantalla después de "Ingresar" en la pantalla de bienvenida.
/// El usuario elige primero el rubro de servicio (Transporte
/// Alternativo / Taxi / Mototaxi) y recién en la pantalla siguiente
/// (OrganizacionSelectScreen) ve las organizaciones de ese rubro en
/// particular, en vez de ver de entrada todas las organizaciones de
/// la plataforma mezcladas.
///
/// No consulta la base de datos -- las 3 opciones son fijas (ver
/// TipoOrganizacion). La organización disponible o no dentro de cada
/// rubro se resuelve recién en la pantalla siguiente.
class TipoOrganizacionSelectScreen extends StatelessWidget {
  const TipoOrganizacionSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('¿Qué tipo de servicio buscás?')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rubros disponibles',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Elegí el rubro para ver las organizaciones asociadas.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: TipoOrganizacion.values.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final tipo = TipoOrganizacion.values[index];
                  return _TipoCard(
                    tipo: tipo,
                    onTap: () => Navigator.of(context).pushNamed(
                      AppRouter.organizacionSelect,
                      arguments: tipo,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipoCard extends StatelessWidget {
  final TipoOrganizacion tipo;
  final VoidCallback onTap;

  const _TipoCard({required this.tipo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(tipo.icono, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tipo.label,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      tipo.descripcion,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
