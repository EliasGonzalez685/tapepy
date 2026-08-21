import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/cuota_plataforma_service.dart';

const _meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

const _labelsEstado = {
  'pagado': 'Pagado',
  'atrasado': 'Atrasado',
  'pendiente': 'Pendiente',
  'exonerado': 'Exonerado',
};

const _labelsRol = {
  'presidente_asociacion': 'Presidente de Asociación',
  'presidente_parada': 'Presidente de Parada',
  'conductor': 'Conductor',
};

/// Panel del dueño de plataforma: cobro del servicio de TapePy en sí
/// (distinto del panel de "Balance de pagos" interno de cada
/// asociación). Acá genera el cargo del mes para una organización y ve
/// quién está al día y quién en deuda, agrupado por parada -- puede
/// además marcar a mano un pago o exonerar a alguien.
class CuotasPlataformaScreen extends StatefulWidget {
  final Usuario usuario;
  const CuotasPlataformaScreen({super.key, required this.usuario});

  @override
  State<CuotasPlataformaScreen> createState() => _CuotasPlataformaScreenState();
}

class _CuotasPlataformaScreenState extends State<CuotasPlataformaScreen> {
  final _cuotaService = CuotaPlataformaService();
  final _organizacionService = OrganizacionService();
  late Future<List<OrganizacionItem>> _organizacionesFuture;
  OrganizacionItem? _seleccionada;
  Future<List<CuotaPlataformaItem>>? _cuotasFuture;

  @override
  void initState() {
    super.initState();
    _organizacionesFuture = _organizacionService.cargarOrganizaciones();
  }

  void _seleccionar(OrganizacionItem organizacion) {
    setState(() {
      _seleccionada = organizacion;
      _cuotasFuture = _cuotaService.cargarPorOrganizacion(organizacion.id);
    });
  }

  void _refrescar() {
    if (_seleccionada == null) return;
    setState(() {
      _cuotasFuture = _cuotaService.cargarPorOrganizacion(_seleccionada!.id);
    });
  }

  Future<void> _generarCargo() async {
    final organizacion = _seleccionada;
    if (organizacion == null) return;
    final generado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioGenerarCargo(
        organizacionId: organizacion.id,
        creadoPor: widget.usuario.id,
        service: _cuotaService,
      ),
    );
    if (generado == true) _refrescar();
  }

  Future<void> _cambiarEstado(CuotaPlataformaItem cuota, String estado) async {
    try {
      await _cuotaService.marcarEstado(cuotaId: cuota.id, estado: estado);
      _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo actualizar. Intentá de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuotas de plataforma')),
      floatingActionButton: _seleccionada == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _generarCargo,
              backgroundColor: AppTheme.rojoInstitucional,
              icon: const Icon(Icons.add),
              label: const Text('Generar cobro del mes'),
            ),
      body: FutureBuilder<List<OrganizacionItem>>(
        future: _organizacionesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final organizaciones = snapshot.data ?? [];
          if (organizaciones.isEmpty) {
            return const Center(child: Text('Todavía no hay ninguna organización cargada.'));
          }
          _seleccionada ??= organizaciones.first;
          _cuotasFuture ??= _cuotaService.cargarPorOrganizacion(_seleccionada!.id);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: DropdownButtonFormField<String>(
                  value: _seleccionada!.id,
                  decoration: const InputDecoration(
                    labelText: 'Organización',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: organizaciones
                      .map((o) => DropdownMenuItem(value: o.id, child: Text(o.nombre)))
                      .toList(),
                  onChanged: (id) {
                    final organizacion = organizaciones.firstWhere((o) => o.id == id);
                    _seleccionar(organizacion);
                  },
                ),
              ),
              Expanded(
                child: FutureBuilder<List<CuotaPlataformaItem>>(
                  future: _cuotasFuture,
                  builder: (context, snapshotCuotas) {
                    if (snapshotCuotas.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshotCuotas.hasError) {
                      return Center(child: Text('No se pudo cargar: ${snapshotCuotas.error}'));
                    }
                    final cuotas = snapshotCuotas.data ?? [];
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
                                  'Todavía no generaste ningún cobro para esta organización',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    final grupos = _cuotaService.agruparPorParada(cuotas);
                    final totalEnDeuda = cuotas.where((c) => c.enDeuda).length;

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ResumenOrganizacion(total: cuotas.length, enDeuda: totalEnDeuda),
                        const SizedBox(height: 16),
                        ...grupos.map((grupo) => _GrupoParadaCard(
                              grupo: grupo,
                              onCambiarEstado: _cambiarEstado,
                            )),
                        const SizedBox(height: 72),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
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
            etiqueta: 'En deuda',
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
  final GrupoCuotasPorParada grupo;
  final void Function(CuotaPlataformaItem cuota, String estado) onCambiarEstado;
  const _GrupoParadaCard({required this.grupo, required this.onCambiarEstado});

  @override
  Widget build(BuildContext context) {
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
        children: grupo.cuotas.map((cuota) => _CuotaRow(cuota: cuota, onCambiarEstado: onCambiarEstado)).toList(),
      ),
    );
  }
}

class _CuotaRow extends StatelessWidget {
  final CuotaPlataformaItem cuota;
  final void Function(CuotaPlataformaItem cuota, String estado) onCambiarEstado;
  const _CuotaRow({required this.cuota, required this.onCambiarEstado});

  Color get _color {
    if (cuota.enDeuda) return AppTheme.estadoUrgente;
    switch (cuota.estado) {
      case 'pagado':
      case 'exonerado':
        return AppTheme.estadoOk;
      case 'pendiente':
        return AppTheme.estadoAtencion;
      default:
        return Colors.grey;
    }
  }

  String get _labelEstado => cuota.enDeuda ? 'Atrasado' : (_labelsEstado[cuota.estado] ?? cuota.estado);

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return ListTile(
      dense: true,
      title: Text(cuota.usuarioNombre ?? 'Usuario'),
      subtitle: Text(
        '${_labelsRol[cuota.usuarioRol] ?? cuota.usuarioRol ?? ''} · ${_meses[cuota.mes]} ${cuota.anio} · ₲ ${formatoMonto.format(cuota.monto)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_labelEstado, style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 11)),
          ),
          PopupMenuButton<String>(
            onSelected: (estado) => onCambiarEstado(cuota, estado),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'pagado', child: Text('Marcar pagado')),
              PopupMenuItem(value: 'pendiente', child: Text('Marcar pendiente')),
              PopupMenuItem(value: 'atrasado', child: Text('Marcar atrasado')),
              PopupMenuItem(value: 'exonerado', child: Text('Exonerar')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormularioGenerarCargo extends StatefulWidget {
  final String organizacionId;
  final String creadoPor;
  final CuotaPlataformaService service;
  const _FormularioGenerarCargo({required this.organizacionId, required this.creadoPor, required this.service});

  @override
  State<_FormularioGenerarCargo> createState() => _FormularioGenerarCargoState();
}

class _FormularioGenerarCargoState extends State<_FormularioGenerarCargo> {
  final _montoController = TextEditingController();
  final _hoy = DateTime.now();
  late int _mes = _hoy.month;
  late int _anio = _hoy.year;
  DateTime _fechaVencimiento = DateTime(DateTime.now().year, DateTime.now().month, 10);
  bool _generando = false;
  String? _error;

  @override
  void dispose() {
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _elegirFechaVencimiento() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaVencimiento,
      firstDate: DateTime(_hoy.year - 1),
      lastDate: DateTime(_hoy.year + 1),
    );
    if (fecha != null) setState(() => _fechaVencimiento = fecha);
  }

  Future<void> _generar() async {
    final monto = double.tryParse(_montoController.text.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Ingresá un monto válido');
      return;
    }
    setState(() {
      _generando = true;
      _error = null;
    });
    try {
      final cantidad = await widget.service.generarCargoMensual(
        organizacionId: widget.organizacionId,
        mes: _mes,
        anio: _anio,
        monto: monto,
        fechaVencimiento: _fechaVencimiento,
        creadoPor: widget.creadoPor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se generó el cargo para $cantidad miembros (los que ya lo tenían no se duplican).')),
      );
      Navigator.of(context).pop(true);
    } on CuotaPlataformaException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo generar el cargo. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
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
          Text('Generar cobro del mes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Se crea un cargo individual para cada presidente de asociación, presidente de parada y conductor de esta organización.',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _mes,
                  decoration: const InputDecoration(labelText: 'Mes', border: OutlineInputBorder(), isDense: true),
                  items: List.generate(
                      12, (i) => DropdownMenuItem(value: i + 1, child: Text(_meses[i + 1]))),
                  onChanged: (v) => setState(() => _mes = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: '$_anio',
                  decoration: const InputDecoration(labelText: 'Año', border: OutlineInputBorder(), isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _anio = int.tryParse(v) ?? _anio,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _montoController,
            decoration: const InputDecoration(labelText: 'Monto (₲)', border: OutlineInputBorder(), isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _elegirFechaVencimiento,
            icon: const Icon(Icons.event_outlined),
            label: Text('Vence: ${formatoFecha.format(_fechaVencimiento)}'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _generando ? null : _generar,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
            child: _generando
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Generar'),
          ),
        ],
      ),
    );
  }
}
