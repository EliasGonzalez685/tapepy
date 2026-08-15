import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../parada/data/parada_presidente_service.dart';

/// Vista de solo lectura para el presidente de asociación: qué empresa
/// tiene convenio de publicidad con cada parada de la organización.
/// Los convenios los carga el presidente de cada parada; acá solo se
/// consultan todos juntos.
class ConveniosOrganizacionScreen extends StatefulWidget {
  final String? organizacionId;
  const ConveniosOrganizacionScreen({super.key, this.organizacionId});

  @override
  State<ConveniosOrganizacionScreen> createState() => _ConveniosOrganizacionScreenState();
}

class _ConveniosOrganizacionScreenState extends State<ConveniosOrganizacionScreen> {
  final _service = ParadaPresidenteService();
  late Future<List<ConvenioItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarConveniosOrganizacion(organizacionId: widget.organizacionId);
  }

  Future<void> _refrescar() async {
    setState(() =>
        _future = _service.cargarConveniosOrganizacion(organizacionId: widget.organizacionId));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CONVENIOS DE PUBLICIDAD')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<ConvenioItem>>(
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
            final convenios = snapshot.data ?? [];
            if (convenios.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          Icon(Icons.handshake_outlined,
                              size: 40, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          const Text(
                            'Todavía no hay convenios cargados en ninguna parada',
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
              itemCount: convenios.length,
              itemBuilder: (context, index) {
                final item = convenios[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        IconBadge(
                          icono: Icons.handshake_outlined,
                          color: item.activo ? AppTheme.rojoInstitucional : Colors.grey.shade400,
                          diametro: 44,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.empresaNombre,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                item.paradaNombre ?? 'Parada sin nombre',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                              if (item.descripcion != null && item.descripcion!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(item.descripcion!, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ],
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
