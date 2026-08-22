import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../features/asociacion/data/parada_detalle_service.dart';
import '../../features/conductor/data/conductor_service.dart' show VehiculoInfo;

/// Atajo para abrir el detalle de vehículos de un conductor desde
/// cualquier pantalla que ya tenga un [ParadaDetalleService] a mano
/// (presidente de asociación o de parada) — pueden ver marca, modelo,
/// año, color, chapa y las fotos (pedido de Elias 2026-08-22: quiere
/// ver qué vehículo maneja cada conductor DENTRO de la app, aparte del
/// listado imprimible que ya existía) y también alternar cuáles
/// vehículos entran en los próximos listados impresos.
void mostrarVehiculosConductorSheet(
  BuildContext context, {
  required String conductorId,
  required String nombreConductor,
  required ParadaDetalleService service,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => VehiculosConductorSheet(
      conductorId: conductorId,
      nombreConductor: nombreConductor,
      service: service,
    ),
  );
}

/// Vehículos de un conductor puntual: el presidente (de parada o de
/// asociación) puede ver el detalle completo y las fotos, y alternar
/// cuáles vehículos entran en los próximos listados impresos — no puede
/// editar marca, modelo, chapa ni nada más de eso, solo ese switch (la
/// RLS lo blinda del lado del servidor también, ver migración 0029).
class VehiculosConductorSheet extends StatefulWidget {
  final String conductorId;
  final String nombreConductor;
  final ParadaDetalleService service;
  const VehiculosConductorSheet({
    super.key,
    required this.conductorId,
    required this.nombreConductor,
    required this.service,
  });

  @override
  State<VehiculosConductorSheet> createState() => _VehiculosConductorSheetState();
}

class _VehiculosConductorSheetState extends State<VehiculosConductorSheet> {
  late Future<List<VehiculoInfo>> _future;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = widget.service.cargarVehiculosDeConductor(widget.conductorId);
  }

  Future<void> _alternar(VehiculoInfo vehiculo, bool valor) async {
    if (vehiculo.id == null) return;
    try {
      await widget.service.alternarVehiculoEnListado(vehiculoId: vehiculo.id!, valor: valor);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo actualizar. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(_cargar);
    }
  }

  void _verFoto(String path) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: FutureBuilder<String>(
          future: widget.service.obtenerUrlFirmada(path),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              );
            }
            return InteractiveViewer(
              child: Image.network(
                snapshot.data!,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('No se pudo cargar la foto', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _miniatura(String? path, String etiqueta) {
    if (path == null) {
      return Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: Text('Sin foto\n$etiqueta',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      );
    }
    return GestureDetector(
      onTap: () => _verFoto(path),
      child: Container(
        width: 90,
        height: 90,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.rojoInstitucional.withValues(alpha: 0.3)),
        ),
        child: FutureBuilder<String>(
          future: widget.service.obtenerUrlFirmada(path),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            return Image.network(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Vehículos de ${widget.nombreConductor}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Solo para ver -- el switch elige cuáles entran en los próximos listados impresos.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: FutureBuilder<List<VehiculoInfo>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final vehiculos = snapshot.data ?? [];
                if (vehiculos.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('Todavía no cargó ningún vehículo.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: vehiculos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final vehiculo = vehiculos[index];
                    final titulo = [vehiculo.marca, vehiculo.modelo]
                        .where((e) => e != null && e.isNotEmpty)
                        .join(' ');
                    final detalle = [
                      if (vehiculo.anio != null) '${vehiculo.anio}',
                      if (vehiculo.color != null && vehiculo.color!.isNotEmpty) vehiculo.color!,
                    ].join(' · ');
                    return Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(titulo.isEmpty ? (vehiculo.chapa ?? 'Vehículo') : titulo,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            if (vehiculo.chapa != null) ...[
                              const SizedBox(height: 2),
                              Text('Chapa: ${vehiculo.chapa}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                            if (detalle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(detalle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _miniatura(vehiculo.fotoFrenteChapa, 'Frente'),
                                const SizedBox(width: 10),
                                _miniatura(vehiculo.fotoLejos, 'De lejos'),
                              ],
                            ),
                            const Divider(height: 24),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: AppTheme.rojoInstitucional,
                              title: const Text('Incluir en próximos listados impresos'),
                              value: vehiculo.incluirEnListado,
                              onChanged: (valor) => _alternar(vehiculo, valor),
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
        ],
      ),
    );
  }
}
