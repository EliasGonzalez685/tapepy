import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/solicitud_organizacion_service.dart';

/// Bandeja de pedidos de organizaciones nuevas (ver
/// SolicitarOrganizacionScreen), exclusiva del dueño de plataforma. Al
/// aceptar, la organización se crea de cero (RPC
/// aprobar_solicitud_organizacion) y ya queda disponible en el selector
/// de organizaciones de la app.
class SolicitudesOrganizacionScreen extends StatefulWidget {
  const SolicitudesOrganizacionScreen({super.key});

  @override
  State<SolicitudesOrganizacionScreen> createState() =>
      _SolicitudesOrganizacionScreenState();
}

class _SolicitudesOrganizacionScreenState
    extends State<SolicitudesOrganizacionScreen> {
  final _service = SolicitudOrganizacionService();
  late Future<List<SolicitudOrganizacionItem>> _future;
  final Set<String> _procesando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _service.listarPendientes();
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await _future;
  }

  Future<void> _aceptar(SolicitudOrganizacionItem item) async {
    setState(() => _procesando.add(item.id));
    try {
      await _service.aprobar(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.nombreOrganizacion}" ya está dada de alta')),
      );
      await _refrescar();
    } on SolicitudOrganizacionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo aprobar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _procesando.remove(item.id));
    }
  }

  Future<void> _rechazar(SolicitudOrganizacionItem item) async {
    final motivoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Rechazar el pedido de "${item.nombreOrganizacion}"?'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Rechazar', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando.add(item.id));
    try {
      final motivo = motivoController.text.trim();
      await _service.rechazar(item.id, motivo: motivo.isEmpty ? null : motivo);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Se rechazó el pedido de ${item.nombreOrganizacion}')));
      await _refrescar();
    } on SolicitudOrganizacionException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo rechazar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _procesando.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitudes de organización')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<SolicitudOrganizacionItem>>(
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
                          Icon(Icons.domain_add_outlined,
                              size: 40, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          const Text(
                            'No hay solicitudes de organización pendientes',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
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
                                icono: Icons.domain_add_outlined,
                                color: AppTheme.estadoAtencion,
                                diametro: 44),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.nombreOrganizacion,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (item.tipo != null) item.tipo!.label,
                                      'Presidente: ${item.nombrePresidente}',
                                    ].join(' · '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  Text(
                                    'Pedida el ${formatoFecha.format(item.creadoEn)}',
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _rechazar(item),
                                style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(context).colorScheme.error),
                                child: const Text('Rechazar'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => _aceptar(item),
                                style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                                child: const Text('Aceptar'),
                              ),
                            ],
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
