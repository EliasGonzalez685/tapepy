import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../plataforma/data/cuota_plataforma_service.dart';

const _labelsEstado = {
  'pagado': 'Pagado',
  'exonerado': 'Exonerado',
  'pendiente': 'Pendiente',
  'moroso': 'Moroso',
};

const _labelsRol = {
  'presidente_asociacion': 'Presidente de Asociación',
  'presidente_parada': 'Presidente de Parada',
  'conductor': 'Conductor',
};

/// Vista de solo lectura para el presidente de asociación: cómo está
/// cada parada con la cuota de plataforma (lo que se le paga al dueño
/// por el servicio de TapePy, no las cuotas internas). Autoservicio
/// puro -- cada quien reporta su propio pago, acá solo se ve el
/// estado del mes en curso, agrupado por parada. Gestionar el cobro
/// en sí (editar monto, marcar a mano) queda exclusivo del dueño.
class EstadoPlataformaOrganizacionScreen extends StatefulWidget {
  final String organizacionId;
  const EstadoPlataformaOrganizacionScreen({super.key, required this.organizacionId});

  @override
  State<EstadoPlataformaOrganizacionScreen> createState() => _EstadoPlataformaOrganizacionScreenState();
}

class _EstadoPlataformaOrganizacionScreenState extends State<EstadoPlataformaOrganizacionScreen> {
  final _service = CuotaPlataformaService();
  late Future<List<EstadoCuotaPlataforma>> _future;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _service.cargarEstadoOrganizacion(widget.organizacionId);
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estado de pagos a la plataforma')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<EstadoCuotaPlataforma>>(
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
            final estados = snapshot.data ?? [];
            if (estados.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(Icons.workspace_premium_outlined,
                            size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text('Todavía no hay miembros pagadores en esta organización',
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              );
            }
            final grupos = _service.agruparPorParada(estados);
            final totalEnDeuda = estados.where((e) => e.enDeuda).length;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ResumenOrganizacion(total: estados.length, enDeuda: totalEnDeuda),
                const SizedBox(height: 16),
                ...grupos.map((grupo) => _GrupoParadaCard(grupo: grupo)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResumenOrganizacion extends StatelessWidget {
  final int total;
  final int enDeuda;
  const _ResumenOrganizacion({required this.total, required this.enDeuda});

  @override
  Widget build(BuildContext context) {
    final alDia = total - enDeuda;
    return Row(
      children: [
        Expanded(
          child: _StatMini(valor: '$alDia', etiqueta: 'Al día', color: AppTheme.estadoOk),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatMini(
            valor: '$enDeuda',
            etiqueta: 'Morosos',
            color: enDeuda > 0 ? AppTheme.estadoUrgente : Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _StatMini extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final Color color;
  const _StatMini({required this.valor, required this.etiqueta, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(valor,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            Text(etiqueta,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _GrupoParadaCard extends StatelessWidget {
  final GrupoEstadoCuotaPlataforma grupo;
  const _GrupoParadaCard({required this.grupo});

  @override
  Widget build(BuildContext context) {
    final colorBadge = grupo.enDeuda > 0 ? AppTheme.estadoUrgente : AppTheme.estadoOk;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: IconBadge(icono: Icons.location_pin, color: colorBadge, diametro: 40),
        title: Text(grupo.paradaNombre ?? 'Sin parada asignada'),
        subtitle: Text(
          grupo.enDeuda > 0 ? '${grupo.enDeuda} de ${grupo.total} morosos' : 'Todos al día (${grupo.total})',
          style: TextStyle(color: colorBadge, fontWeight: FontWeight.w600),
        ),
        children: grupo.estados.map((e) => _EstadoRow(estado: e)).toList(),
      ),
    );
  }
}

class _EstadoRow extends StatelessWidget {
  final EstadoCuotaPlataforma estado;
  const _EstadoRow({required this.estado});

  Color get _color {
    switch (estado.estado) {
      case 'pagado':
      case 'exonerado':
        return AppTheme.estadoOk;
      case 'moroso':
        return AppTheme.estadoUrgente;
      default:
        return AppTheme.estadoAtencion;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return ListTile(
      dense: true,
      title: Text(estado.nombre ?? 'Usuario'),
      subtitle: Text('${_labelsRol[estado.rol] ?? estado.rol ?? ''} · ₲ ${formatoMonto.format(estado.monto)}'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: _color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(_labelsEstado[estado.estado] ?? estado.estado,
            style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 11)),
      ),
    );
  }
}
