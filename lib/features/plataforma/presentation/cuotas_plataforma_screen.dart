import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/cuota_plataforma_service.dart';

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

/// Panel del dueño de plataforma: cobro del servicio de TapePy en sí
/// (distinto del panel de "Balance de pagos" interno de cada
/// asociación). Modelo autoservicio (pedido de Elias 2026-08-21): ya
/// no se "genera" ningún cargo -- cada quien reporta su propio pago
/// desde su Mis pagos. Acá el dueño solo ve el estado del mes en curso
/// de toda la organización, agrupado por parada, puede editar el
/// monto fijo mensual, y a mano marcar un pago (ej. cobrado en
/// efectivo en persona) o exonerar a alguien.
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
  Future<List<EstadoCuotaPlataforma>>? _estadosFuture;

  @override
  void initState() {
    super.initState();
    _organizacionesFuture = _organizacionService.cargarOrganizaciones();
  }

  void _seleccionar(OrganizacionItem organizacion) {
    setState(() {
      _seleccionada = organizacion;
      _estadosFuture = _cuotaService.cargarEstadoOrganizacion(organizacion.id);
    });
  }

  void _refrescar() {
    if (_seleccionada == null) return;
    setState(() {
      _estadosFuture = _cuotaService.cargarEstadoOrganizacion(_seleccionada!.id);
    });
  }

  Future<void> _editarMonto() async {
    final organizacion = _seleccionada;
    if (organizacion == null) return;
    final montoActual = await _cuotaService.obtenerMonto(organizacion.id);
    if (!mounted) return;
    final cambiado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _FormularioEditarMonto(
        organizacionId: organizacion.id,
        montoActual: montoActual,
        service: _cuotaService,
      ),
    );
    if (cambiado == true) _refrescar();
  }

  Future<void> _cambiarEstado(EstadoCuotaPlataforma estado, String nuevoEstado) async {
    try {
      if (estado.cuotaId != null) {
        await _cuotaService.marcarEstado(cuotaId: estado.cuotaId!, estado: nuevoEstado);
      } else {
        // Todavía no tiene ninguna fila del mes (autoservicio puro) --
        // el override manual del dueño la crea directamente.
        await _cuotaService.registrarManual(
          usuarioId: estado.usuarioId,
          estado: nuevoEstado,
          registradoPor: widget.usuario.id,
        );
      }
      _refrescar();
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is CuotaPlataformaException ? e.message : 'No se pudo actualizar. Intentá de nuevo.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuotas de plataforma'),
        actions: [
          if (_seleccionada != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Editar monto mensual',
              onPressed: _editarMonto,
            ),
        ],
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
          _estadosFuture ??= _cuotaService.cargarEstadoOrganizacion(_seleccionada!.id);

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
                child: FutureBuilder<List<EstadoCuotaPlataforma>>(
                  future: _estadosFuture,
                  builder: (context, snapshotEstados) {
                    if (snapshotEstados.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshotEstados.hasError) {
                      return Center(child: Text('No se pudo cargar: ${snapshotEstados.error}'));
                    }
                    final estados = snapshotEstados.data ?? [];
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
                                const Text(
                                  'Todavía no hay miembros pagadores en esta organización',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    final grupos = _cuotaService.agruparPorParada(estados);
                    final totalEnDeuda = estados.where((e) => e.enDeuda).length;

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ResumenOrganizacion(total: estados.length, enDeuda: totalEnDeuda),
                        const SizedBox(height: 16),
                        ...grupos.map((grupo) => _GrupoParadaCard(
                              grupo: grupo,
                              onCambiarEstado: _cambiarEstado,
                            )),
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
  final void Function(EstadoCuotaPlataforma estado, String nuevoEstado) onCambiarEstado;
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
          grupo.enDeuda > 0 ? '${grupo.enDeuda} de ${grupo.total} morosos' : 'Todos al día (${grupo.total})',
          style: TextStyle(color: colorBadge, fontWeight: FontWeight.w600),
        ),
        children: grupo.estados.map((e) => _EstadoRow(estado: e, onCambiarEstado: onCambiarEstado)).toList(),
      ),
    );
  }
}

class _EstadoRow extends StatelessWidget {
  final EstadoCuotaPlataforma estado;
  final void Function(EstadoCuotaPlataforma estado, String nuevoEstado) onCambiarEstado;
  const _EstadoRow({required this.estado, required this.onCambiarEstado});

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
      subtitle: Text(
        '${_labelsRol[estado.rol] ?? estado.rol ?? ''} · ₲ ${formatoMonto.format(estado.monto)}',
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
            child: Text(_labelsEstado[estado.estado] ?? estado.estado,
                style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 11)),
          ),
          PopupMenuButton<String>(
            onSelected: (nuevoEstado) => onCambiarEstado(estado, nuevoEstado),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'pagado', child: Text('Marcar pagado')),
              PopupMenuItem(value: 'exonerado', child: Text('Exonerar')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormularioEditarMonto extends StatefulWidget {
  final String organizacionId;
  final double montoActual;
  final CuotaPlataformaService service;
  const _FormularioEditarMonto({required this.organizacionId, required this.montoActual, required this.service});

  @override
  State<_FormularioEditarMonto> createState() => _FormularioEditarMontoState();
}

class _FormularioEditarMontoState extends State<_FormularioEditarMonto> {
  late final _montoController = TextEditingController(text: widget.montoActual.toStringAsFixed(0));
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final monto = double.tryParse(_montoController.text.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Ingresá un monto válido');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.editarMonto(organizacionId: widget.organizacionId, monto: monto);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'No se pudo guardar. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
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
          Text('Monto mensual de la cuota', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Lo que cada persona paga por mes. Días 1 al 15 son de gracia; desde el 16, quien no pagó aparece como moroso.',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _montoController,
            decoration: const InputDecoration(labelText: 'Monto (₲)', border: OutlineInputBorder(), isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
            child: _guardando
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
