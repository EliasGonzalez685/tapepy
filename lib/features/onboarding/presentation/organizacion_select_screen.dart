import 'package:flutter/material.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';

/// Elegir con qué organización/cliente entrar. Por ahora Traude es la
/// única, cargada a mano acá mismo.
///
/// TODO cuando exista una segunda organización real: la tabla
/// `organizaciones` hoy tiene RLS que bloquea a usuarios anónimos (sin
/// sesión), así que no se puede listar dinámicamente antes de loguearse
/// sin antes sumar una vía de acceso público segura (ej. una vista/RPC
/// que solo exponga id, nombre y logo de organizaciones activas). No
/// hacerlo con una política que abra la tabla entera a anon.
class OrganizacionSelectScreen extends StatelessWidget {
  const OrganizacionSelectScreen({super.key});

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
            _OrganizacionCard(
              nombre: 'Traude',
              subtitulo: 'Ciudad del Este, Paraguay',
              logoAsset: 'assets/images/traude_logo.png',
              logoDiametro: 64,
              onTap: () => Navigator.of(context).pushNamed(AppRouter.login),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrganizacionCard extends StatelessWidget {
  final String nombre;
  final String subtitulo;
  final String? logoAsset;
  final double logoDiametro;
  final VoidCallback onTap;

  const _OrganizacionCard({
    required this.nombre,
    required this.subtitulo,
    required this.onTap,
    this.logoAsset,
    this.logoDiametro = 48,
  });

  Widget _logoCirculo(String asset, double diametro) {
    return ClipOval(
      child: Image.asset(asset, width: diametro, height: diametro, fit: BoxFit.cover),
    );
  }

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
              logoAsset != null
                  ? _logoCirculo(logoAsset!, logoDiametro)
                  : IconBadge(
                      icono: Icons.apartment,
                      color: AppTheme.rojoInstitucional,
                      diametro: logoDiametro,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      subtitulo,
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
