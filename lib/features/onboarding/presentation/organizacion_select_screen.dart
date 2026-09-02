import 'package:flutter/material.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/data/organizacion_branding_service.dart';
import '../../../shared/models/organizacion_branding.dart';

/// Elegir con qué organización/cliente entrar. Lista todas las
/// organizaciones activas (Traude, FETACE, y las que se sumen
/// después) leyéndolas de la tabla `organizaciones`, que tiene una
/// política RLS pública para filas activas — no hace falta haber
/// iniciado sesión para verla.
class OrganizacionSelectScreen extends StatefulWidget {
  const OrganizacionSelectScreen({super.key});

  @override
  State<OrganizacionSelectScreen> createState() =>
      _OrganizacionSelectScreenState();
}

class _OrganizacionSelectScreenState extends State<OrganizacionSelectScreen> {
  final _service = OrganizacionBrandingService();
  late Future<List<OrganizacionBranding>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.listarActivas();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Elegí tu organización')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Organizaciones disponibles',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Elegí la asociación con la que querés ingresar.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<OrganizacionBranding>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child: Text('No se pudo cargar: ${snapshot.error}'));
                  }
                  final organizaciones = snapshot.data ?? [];
                  if (organizaciones.isEmpty) {
                    return const Center(
                        child: Text('Todavía no hay organizaciones activas.'));
                  }
                  return ListView.separated(
                    itemCount: organizaciones.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final org = organizaciones[index];
                      return _OrganizacionCard(
                        organizacion: org,
                        onTap: () => Navigator.of(context).pushNamed(
                          AppRouter.login,
                          arguments: org,
                        ),
                      );
                    },
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

class _OrganizacionCard extends StatelessWidget {
  final OrganizacionBranding organizacion;
  final VoidCallback onTap;

  const _OrganizacionCard({required this.organizacion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  organizacion.logoAsset,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      organizacion.nombre,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      organizacion.tagline,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
