import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../features/asociacion/data/parada_detalle_service.dart';
import '../utils/imprimir_documento.dart';
import 'icon_badge.dart';

/// Atajo para abrir los documentos de un conductor puntual desde
/// cualquier pantalla que ya tenga un [ParadaDetalleService] a mano
/// (presidente de asociación o de parada) -- pedido de Elias
/// 2026-08-22: sus autoridades a veces piden documentos de un chofer y
/// los choferes tardan en pasarlos, así que ambos presidentes necesitan
/// poder abrirlos ellos mismos, ya preparados, en cualquier momento.
void mostrarDocumentosConductorSheet(
  BuildContext context, {
  required String conductorId,
  required String nombreConductor,
  required ParadaDetalleService service,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => DocumentosConductorSheet(
      conductorId: conductorId,
      nombreConductor: nombreConductor,
      service: service,
    ),
  );
}

class DocumentosConductorSheet extends StatefulWidget {
  final String conductorId;
  final String nombreConductor;
  final ParadaDetalleService service;
  const DocumentosConductorSheet({
    super.key,
    required this.conductorId,
    required this.nombreConductor,
    required this.service,
  });

  @override
  State<DocumentosConductorSheet> createState() => _DocumentosConductorSheetState();
}

class _DocumentosConductorSheetState extends State<DocumentosConductorSheet> {
  late Future<List<DocumentoItem>> _future;

  static const _labelsTipo = {
    'cedula': 'Cédula',
    'licencia_conducir': 'Licencia de conducir',
    'antecedentes_policiales': 'Antecedentes policiales',
    'seguro_vehicular': 'Seguro vehicular',
    'revision_tecnica': 'Revisión técnica',
    'carta_verde': 'Carta verde',
    'habilitacion_vehicular': 'Habilitación vehicular',
    'cedula_verde': 'Cédula verde',
    'habilitacion_municipal': 'Habilitación municipal',
    'otro': 'Otro documento',
  };

  static const _labelsEstado = {'vigente': 'Vigente', 'por_vencer': 'Por vencer', 'vencido': 'Vencido'};

  @override
  void initState() {
    super.initState();
    _future = widget.service.cargarDocumentosDeConductor(widget.conductorId);
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'vigente':
        return AppTheme.estadoOk;
      case 'por_vencer':
        return AppTheme.estadoAtencion;
      case 'vencido':
        return AppTheme.estadoUrgente;
      default:
        return Colors.grey;
    }
  }

  String _labelTipo(DocumentoItem item) =>
      item.tipo == 'otro' && item.descripcion != null && item.descripcion!.isNotEmpty
          ? item.descripcion!
          : (_labelsTipo[item.tipo] ?? item.tipo);

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
          Text('Documentos de ${widget.nombreConductor}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Tocá un documento para verlo, guardarlo o imprimirlo.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
            child: FutureBuilder<List<DocumentoItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final documentos = snapshot.data ?? [];
                if (documentos.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('Todavía no cargó ningún documento.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: documentos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = documentos[index];
                    final color = _colorEstado(item.estado);
                    return Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => imprimirArchivoDocumento(
                          context: context,
                          obtenerUrlFirmada: widget.service.obtenerUrlFirmada,
                          path: item.archivoUrl,
                          nombreSugerido: item.nombreArchivo ?? '${_labelTipo(item)}.pdf',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              IconBadge(icono: Icons.description_outlined, color: color, diametro: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(_labelTipo(item),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _labelsEstado[item.estado] ?? item.estado,
                                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_outlined),
                                tooltip: 'Compartir',
                                onPressed: () => compartirArchivoDocumento(
                                  context: context,
                                  obtenerUrlFirmada: widget.service.obtenerUrlFirmada,
                                  path: item.archivoUrl,
                                  nombreSugerido: item.nombreArchivo ?? '${_labelTipo(item)}.pdf',
                                ),
                              ),
                            ],
                          ),
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
