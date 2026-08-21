import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../plataforma/data/cuota_plataforma_service.dart';

const _meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

const _labelsRol = {
  'presidente_asociacion': 'Presidente de Asociación',
  'presidente_parada': 'Presidente de Parada',
  'conductor': 'Conductor',
};

/// Solo lectura para el presidente de asociación: estado de la cuota de
/// plataforma (lo que cada socio le paga al dueño de TapePy) agrupado
/// por parada. Pedido de Elias 2026-08-21: como mínimo tiene que poder
/// ver el estado de cada parada -- gestionar el cobro en sí (generar
/// cargos, marcar pagado, exonerar) es exclusivo del dueño de
/// plataforma, acá no hay ninguna acción disponible.
class EstadoPlataformaOrganizacionScreen extends StatefulWidget {
  final String organizacionId;
  const EstadoPlataformaOrganizacionScreen({super.key, required this.organizacionId});

  @override
  State<EstadoPlataformaOrganizacionScreen> createState() => _EstadoPlataformaOrganizacionScreenState();
}

class _EstadoPlataformaOrganizacionScreenState extends State<EstadoPlataformaOrganizacionScreen> {
  final _service = CuotaPlataformaService();
  late Future<List<CuotaPlataformaItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarPorOrganizacion(widget.organizacionId);
  }

  Future<void> _refrescar() async {
    setState(() {
      _future = _service.cargarPorOrganizacion(widget.organizacionId);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuota de plataforma por parada')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<CuotaPlataformaItem>>(
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
            final cuotas = snapshot.data ?? [];
            if (cuotas.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(Icons.workspace_premium_outlined,
                            size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                          'El dueño de plataforma todavía no generó ningún cobro para tu organización',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            final grupos = _service.agruparPorParada(cuotas);
            final totalEnDeuda = cuotas.where((c) => c.enDeuda).length;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatMini(
                        valor: '${cuotas.length - totalEnDeuda}',
                        etiqueta: 'Al día',
                        color: AppTheme.estadoOk,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatMini(
                        valor: '$totalEnDeuda',
                        etiqueta: 'En deuda',
                        color: totalEnDeuda > 0 ? AppTheme.estadoUrgente : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
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
  final GrupoCuotasPorParada grupo;
  const _GrupoParadaCard({required this.grupo});

  Color _colorCuota(CuotaPlataformaItem cuota) {
    if (cuota.enDeuda) return AppTheme.estadoUrgente;
    if (cuota.alDia) return AppTheme.estadoOk;
    return AppTheme.estadoAtencion;
  }

  String _labelCuota(CuotaPlataformaItem cuota) {
    if (cuota.enDeuda) return 'Atrasado';
    switch (cuota.estado) {
      case 'pagado':
        return 'Pagado';
      case 'exonerado':
        return 'Exonerado';
      case 'pendiente':
        return 'Pendiente';
      default:
        return cuota.estado;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    final colorBadge = grupo.enDeuda > 0 ? AppTheme.estadoUrgente : AppTheme.estadoOk;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: IconBadge(icono: Icons.location_pin, color: colorBadge, diametro: 40),
        title: Text(grupo.paradaNombre ?? 'Sin parada asignada'),
        subtitle: Text(
          grupo.enDeuda > 0 ? '${grupo.enDeuda} de ${grupo.total} en deuda' : 'Todos al día (${grupo.total})',
          style: TextStyle(color: colorBadge, fontWeight: FontWeight.w600),
        ),
        children: grupo.cuotas.map((cuota) {
          final color = _colorCuota(cuota);
          return ListTile(
            dense: true,
            title: Text(cuota.usuarioNombre ?? 'Usuario'),
            subtitle: Text(
              '${_labelsRol[cuota.usuarioRol] ?? cuota.usuarioRol ?? ''} · ${_meses[cuota.mes]} ${cuota.anio} · ₲ ${formatoMonto.format(cuota.monto)}',
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child:
                  Text(_labelCuota(cuota), style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
            ),
          );
        }).toList(),
      ),
    );
  }
}
