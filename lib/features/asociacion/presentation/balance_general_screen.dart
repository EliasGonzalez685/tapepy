import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../plataforma/data/cuota_plataforma_service.dart';
import '../data/balance_pagos.dart';
import '../data/parada_detalle_service.dart';

const _meses = [
  '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
];

const _labelsEstadoPlataforma = {
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

/// Vista consolidada de TODO lo que se cobra en la organización, por
/// parada y con detalle individual, separado por descripción (pedido
/// de Elias 2026-08-21): cuota de plataforma (a TapePy) en su propia
/// sección, y pagos internos (a la parada/asociación, agrupados por
/// mes y motivo) en la suya -- nunca mezclados.
///
/// La usan 3 roles, cada uno viendo lo que le corresponde gracias a
/// la RLS/RPC de cada fuente (no hay lógica de scoping acá):
/// - Presidente de asociación: toda la organización, todas las paradas.
/// - Presidente de parada: automáticamente queda acotado a su propia
///   parada (tanto RLS de cuotas_mensuales como la RPC de plataforma
///   lo filtran del lado de la base).
/// - Dueño de plataforma: elige la organización desde un selector
///   (mismo patrón que su panel de cuotas de plataforma).
class BalanceGeneralScreen extends StatefulWidget {
  final String? organizacionId;
  final bool seleccionarOrganizacion;
  const BalanceGeneralScreen({
    super.key,
    this.organizacionId,
    this.seleccionarOrganizacion = false,
  });

  @override
  State<BalanceGeneralScreen> createState() => _BalanceGeneralScreenState();
}

class _DatosBalanceGeneral {
  final List<GrupoBalanceParada> internos;
  final List<GrupoEstadoCuotaPlataforma> plataforma;
  _DatosBalanceGeneral({required this.internos, required this.plataforma});
}

class _BalanceGeneralScreenState extends State<BalanceGeneralScreen> {
  final _paradaService = ParadaDetalleService();
  final _plataformaService = CuotaPlataformaService();
  final _organizacionService = OrganizacionService();
  Future<List<OrganizacionItem>>? _organizacionesFuture;
  String? _organizacionIdActual;
  Future<_DatosBalanceGeneral>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.seleccionarOrganizacion) {
      _organizacionesFuture = _organizacionService.cargarOrganizaciones();
    } else {
      _organizacionIdActual = widget.organizacionId;
      // Asignación directa (sin setState): todavía no hubo ningún
      // build, no hace falta pedirle uno nuevo al framework.
      if (_organizacionIdActual != null) {
        _future = _cargarDatos(_organizacionIdActual!);
      }
    }
  }

  void _cargar() {
    final orgId = _organizacionIdActual;
    if (orgId == null) return;
    setState(() {
      _future = _cargarDatos(orgId);
    });
  }

  Future<_DatosBalanceGeneral> _cargarDatos(String organizacionId) async {
    final internos = await _paradaService
        .cargarCuotasParaBalanceOrganizacion(organizacionId)
        .then(agruparBalancePorParada);
    final plataforma = await _plataformaService.cargarEstadoOrganizacion(organizacionId);
    final gruposPlataforma = _plataformaService.agruparPorParada(plataforma);
    return _DatosBalanceGeneral(internos: internos, plataforma: gruposPlataforma);
  }

  void _elegirOrganizacion(OrganizacionItem organizacion) {
    _organizacionIdActual = organizacion.id;
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Balance general')),
      body: widget.seleccionarOrganizacion ? _buildConSelector(context) : _buildContenido(context),
    );
  }

  Widget _buildConSelector(BuildContext context) {
    return FutureBuilder<List<OrganizacionItem>>(
      future: _organizacionesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final organizaciones = snapshot.data ?? [];
        if (organizaciones.isEmpty) {
          return const Center(child: Text('Todavía no hay ninguna organización cargada.'));
        }
        if (_organizacionIdActual == null) {
          // Primera carga: asignación directa, sin setState -- ya
          // estamos dentro de build(), llamar setState acá tiraría
          // "setState called during build".
          _organizacionIdActual = organizaciones.first.id;
          _future = _cargarDatos(_organizacionIdActual!);
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: DropdownButtonFormField<String>(
                value: _organizacionIdActual,
                decoration: const InputDecoration(
                  labelText: 'Organización',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: organizaciones.map((o) => DropdownMenuItem(value: o.id, child: Text(o.nombre))).toList(),
                onChanged: (id) {
                  final organizacion = organizaciones.firstWhere((o) => o.id == id);
                  _elegirOrganizacion(organizacion);
                },
              ),
            ),
            Expanded(child: _buildContenido(context)),
          ],
        );
      },
    );
  }

  Widget _buildContenido(BuildContext context) {
    if (_future == null) {
      return const Center(child: Text('No se pudo determinar la organización.'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        _cargar();
        await _future;
      },
      child: FutureBuilder<_DatosBalanceGeneral>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return ListView(children: [
              const SizedBox(height: 80),
              Center(child: Text('No se pudo cargar: ${snapshot.error}')),
            ]);
          }
          final datos = snapshot.data!;

          // Une las paradas que aparecen en cualquiera de las dos
          // fuentes -- puede haber una parada con pagos internos pero
          // sin nadie todavía en cuota de plataforma, o viceversa.
          final nombresParadas = <String?, String>{};
          for (final g in datos.internos) {
            nombresParadas[g.paradaId] = g.paradaNombre ?? 'Sin parada asignada';
          }
          for (final g in datos.plataforma) {
            nombresParadas.putIfAbsent(g.paradaId, () => g.paradaNombre ?? 'Sin parada asignada');
          }

          if (nombresParadas.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                  child: Column(
                    children: [
                      Icon(Icons.bar_chart_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      const Text('Todavía no hay nada para mostrar acá', textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            );
          }

          final paradaIds = nombresParadas.keys.toList()
            ..sort((a, b) {
              if (a == null) return 1;
              if (b == null) return -1;
              return nombresParadas[a]!.compareTo(nombresParadas[b]!);
            });

          return ListView(
            padding: const EdgeInsets.all(16),
            children: paradaIds.map((paradaId) {
              final interno = datos.internos.firstWhereOrNull((g) => g.paradaId == paradaId);
              final plataforma = datos.plataforma.firstWhereOrNull((g) => g.paradaId == paradaId);
              return _ParadaBalanceCard(
                nombre: nombresParadas[paradaId]!,
                interno: interno,
                plataforma: plataforma,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

class _ParadaBalanceCard extends StatelessWidget {
  final String nombre;
  final GrupoBalanceParada? interno;
  final GrupoEstadoCuotaPlataforma? plataforma;
  const _ParadaBalanceCard({required this.nombre, this.interno, this.plataforma});

  @override
  Widget build(BuildContext context) {
    final enDeudaPlataforma = plataforma?.enDeuda ?? 0;
    final debeInterno = interno != null && (interno!.balance.totalPendiente + interno!.balance.totalAtrasado) > 0;
    final colorBadge = (enDeudaPlataforma > 0 || debeInterno) ? AppTheme.estadoUrgente : AppTheme.estadoOk;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: IconBadge(icono: Icons.location_pin, color: colorBadge, diametro: 40),
        title: Text(nombre),
        subtitle: Text(
          [
            if (plataforma != null) '${plataforma!.enDeuda} de ${plataforma!.total} morosos (plataforma)',
            if (interno != null) '₲ ${NumberFormat.decimalPattern('es').format(interno!.balance.totalPendiente + interno!.balance.totalAtrasado)} pendiente (interno)',
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          if (plataforma != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Cuota de plataforma',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            ...plataforma!.estados.map((e) => _EstadoPlataformaRow(estado: e)),
          ],
          if (interno != null && !interno!.balance.estaVacio) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Pagos internos',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            _TablaInternaPorMesMotivo(balance: interno!.balance),
            const SizedBox(height: 8),
            _TablaInternaPorConductor(balance: interno!.balance),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EstadoPlataformaRow extends StatelessWidget {
  final EstadoCuotaPlataforma estado;
  const _EstadoPlataformaRow({required this.estado});

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
        child: Text(_labelsEstadoPlataforma[estado.estado] ?? estado.estado,
            style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 11)),
      ),
    );
  }
}

class _TablaInternaPorMesMotivo extends StatelessWidget {
  final BalancePagosParada balance;
  const _TablaInternaPorMesMotivo({required this.balance});

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    int? anioActual;
    int? mesActual;
    final widgets = <Widget>[];
    for (final grupo in balance.porMesMotivo) {
      if (grupo.anio != anioActual || grupo.mes != mesActual) {
        anioActual = grupo.anio;
        mesActual = grupo.mes;
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text('${_meses[grupo.mes]} ${grupo.anio}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ));
      }
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(grupo.motivo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            if (grupo.recaudado > 0)
              Text('Recaudado: ₲ ${formatoMonto.format(grupo.recaudado)}',
                  style: const TextStyle(color: AppTheme.estadoOk, fontSize: 12)),
            if (grupo.pendiente > 0)
              Text('Pendiente: ₲ ${formatoMonto.format(grupo.pendiente)}',
                  style: const TextStyle(color: AppTheme.estadoAtencion, fontSize: 12)),
            if (grupo.atrasado > 0)
              Text('Atrasado: ₲ ${formatoMonto.format(grupo.atrasado)}',
                  style: const TextStyle(color: AppTheme.estadoUrgente, fontSize: 12)),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}

class _TablaInternaPorConductor extends StatelessWidget {
  final BalancePagosParada balance;
  const _TablaInternaPorConductor({required this.balance});

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return Column(
      children: balance.porConductor.map((c) {
        return ListTile(
          dense: true,
          title: Text(c.nombre),
          subtitle: Text('${c.cantidadPagos} pago(s)'),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (c.pagado > 0)
                Text('Pagó: ₲ ${formatoMonto.format(c.pagado)}',
                    style: const TextStyle(color: AppTheme.estadoOk, fontSize: 12, fontWeight: FontWeight.w600)),
              if (c.debe > 0)
                Text('Debe: ₲ ${formatoMonto.format(c.debe)}',
                    style:
                        const TextStyle(color: AppTheme.estadoUrgente, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
