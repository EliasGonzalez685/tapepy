import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../features/asociacion/data/parada_detalle_service.dart';
import '../utils/imprimir_documento.dart';
import 'documentos_conductor_sheet.dart';
import 'icon_badge.dart';

const _labelsTipoDocumento = {
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

const _labelsEstadoDocumento = {'vigente': 'Vigente', 'por_vencer': 'Por vencer', 'vencido': 'Vencido'};

const _ordenEstado = {'vencido': 0, 'por_vencer': 1, 'vigente': 2};

Color _colorEstadoDocumento(String estado) {
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

String _labelTipoDocumento(DocumentoItem item) =>
    item.tipo == 'otro' && item.descripcion != null && item.descripcion!.isNotEmpty
        ? item.descripcion!
        : (_labelsTipoDocumento[item.tipo] ?? item.tipo);

/// Documentos de una parada, agrupados por persona en vez de una fila
/// plana por documento -- pedido de Elias 2026-08-22: con muchos
/// conductores cargados, una fila por documento se vuelve repetitiva y
/// desordenada. Acá se ve una tarjeta por conductor (con la cantidad de
/// documentos y el peor estado entre ellos) y al tocarla se abren todos
/// sus documentos -- reusa el mismo sheet que "Ver documentos" desde
/// Miembros. Los documentos propios de la parada (no de un conductor
/// puntual) quedan aparte, en su propia lista chica.
class DocumentosAgrupadosList extends StatelessWidget {
  final Future<List<DocumentoItem>> future;
  final ParadaDetalleService service;
  const DocumentosAgrupadosList({super.key, required this.future, required this.service});

  String _peorEstado(List<DocumentoItem> docs) {
    var peor = 'vigente';
    var peorOrden = 3;
    for (final doc in docs) {
      final orden = _ordenEstado[doc.estado] ?? 3;
      if (orden < peorOrden) {
        peorOrden = orden;
        peor = doc.estado;
      }
    }
    return peor;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DocumentoItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No se pudo cargar: ${snapshot.error}')),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.description_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('No hay documentos por revisar en esta parada',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          );
        }

        final deParada = items.where((i) => i.conductorId == null).toList();
        final porConductor = <String, List<DocumentoItem>>{};
        final nombrePorConductor = <String, String>{};
        for (final item in items.where((i) => i.conductorId != null)) {
          porConductor.putIfAbsent(item.conductorId!, () => []).add(item);
          nombrePorConductor[item.conductorId!] = item.entidad;
        }
        final conductorIds = porConductor.keys.toList()
          ..sort((a, b) =>
              (nombrePorConductor[a] ?? '').toLowerCase().compareTo((nombrePorConductor[b] ?? '').toLowerCase()));

        final formatoFecha = DateFormat('dd/MM/yyyy');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (deParada.isNotEmpty) ...[
              Text('Documentos de la parada',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...deParada.map((item) {
                final color = _colorEstadoDocumento(item.estado);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => imprimirArchivoDocumento(
                      context: context,
                      obtenerUrlFirmada: service.obtenerUrlFirmada,
                      path: item.archivoUrl,
                      nombreSugerido: item.nombreArchivo ?? '${_labelTipoDocumento(item)}.pdf',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          IconBadge(icono: Icons.description_outlined, color: color, diametro: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_labelTipoDocumento(item),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                if (item.fechaVencimiento != null)
                                  Text('Vence ${formatoFecha.format(item.fechaVencimiento!)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(_labelsEstadoDocumento[item.estado] ?? item.estado,
                                style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
            if (conductorIds.isNotEmpty) ...[
              Text('Documentos por conductor',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...conductorIds.map((conductorId) {
                final docs = porConductor[conductorId]!;
                final nombre = nombrePorConductor[conductorId] ?? 'Conductor';
                final peorEstado = _peorEstado(docs);
                final color = _colorEstadoDocumento(peorEstado);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => mostrarDocumentosConductorSheet(
                      context,
                      conductorId: conductorId,
                      nombreConductor: nombre,
                      service: service,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          IconBadge(icono: Icons.folder_outlined, color: color, diametro: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nombre,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                Text('${docs.length} documento${docs.length == 1 ? '' : 's'}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          if (peorEstado != 'vigente')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(_labelsEstadoDocumento[peorEstado] ?? peorEstado,
                                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                            ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }
}
