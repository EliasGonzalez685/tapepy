import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/cuentas_bloqueadas_service.dart';

/// Solo el dueño de plataforma llega a esta pantalla (se enlaza desde
/// dueno_plataforma_home_screen.dart). Lista todas las cuentas que se
/// autobloquearon por 5 intentos fallidos de login seguidos, con un
/// botón para desbloquearlas -- es la única forma de sacarlas del
/// bloqueo, pedido explícito de Elias 2026-08-20.
class CuentasBloqueadasScreen extends StatefulWidget {
  const CuentasBloqueadasScreen({super.key});

  @override
  State<CuentasBloqueadasScreen> createState() => _CuentasBloqueadasScreenState();
}

class _CuentasBloqueadasScreenState extends State<CuentasBloqueadasScreen> {
  final _service = CuentasBloqueadasService();
  late Future<List<CuentaBloqueadaItem>> _future;
  final Set<String> _procesando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _service.cargarBloqueadas();
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await _future;
  }

  Future<void> _desbloquear(CuentaBloqueadaItem item) async {
    setState(() => _procesando.add(item.id));
    try {
      await _service.desbloquear(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${item.nombre} ya puede volver a intentar')));
      await _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo desbloquear. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _procesando.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas bloqueadas')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<CuentaBloqueadaItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('No se pudo cargar: ${snapshot.error}')),
                ],
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          Icon(Icons.lock_open_outlined,
                              size: 40, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          const Text(
                            'No hay ninguna cuenta bloqueada por el momento',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final procesandoItem = _procesando.contains(item.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const IconBadge(
                                icono: Icons.lock_outline, color: AppTheme.estadoUrgente, diametro: 44),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.nombre,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      item.rol.label,
                                      if (item.cedula != null) 'CI ${item.cedula}',
                                      if (item.organizacionNombre != null) item.organizacionNombre!,
                                    ].join(' · '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  Text(item.email,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  Text(
                                    'Bloqueada el ${item.bloqueadoEnTexto} · ${item.intentosFallidos} intentos fallidos',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (procesandoItem)
                          const Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                                height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        else
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () => _desbloquear(item),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                              icon: const Icon(Icons.lock_open_outlined, size: 18),
                              label: const Text('Desbloquear'),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
