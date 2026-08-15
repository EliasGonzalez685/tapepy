import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../features/asociacion/data/parada_detalle_service.dart';
import '../../features/conductor/data/conductor_service.dart' show VehiculoInfo;

/// Atajo para abrir el selector de vehículos de un conductor desde
/// cualquier pantalla que ya tenga un [ParadaDetalleService] a mano
/// (presidente de asociación o de parada — ambos pueden alternar cuáles
/// vehículos entran en los próximos listados impresos).
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
/// asociación) puede ver el detalle y alternar cuáles entran en los
/// próximos listados impresos — no puede editar marca, modelo, chapa
/// ni nada más de eso, solo ese switch (la RLS lo blinda del lado del
/// servidor también, ver migración 0029).
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
            'Elegí cuáles entran en los próximos listados impresos.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<VehiculoInfo>>(
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
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: vehiculos.map((vehiculo) {
                  final titulo = [vehiculo.marca, vehiculo.modelo]
                      .where((e) => e != null && e.isNotEmpty)
                      .join(' ');
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppTheme.rojoInstitucional,
                    title: Text(titulo.isEmpty ? (vehiculo.chapa ?? 'Vehículo') : titulo),
                    subtitle: vehiculo.chapa != null ? Text(vehiculo.chapa!) : null,
                    value: vehiculo.incluirEnListado,
                    onChanged: (valor) => _alternar(vehiculo, valor),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
