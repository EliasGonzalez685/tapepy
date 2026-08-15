import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../data/parada_detalle_service.dart';

/// Carga manual de una cuota mensual para un conductor de una parada.
/// Lo usan tanto el presidente de parada (parada_home_screen.dart) como
/// el presidente de asociación viendo el detalle de una parada
/// (parada_detalle_screen.dart) — por eso vive acá, compartido.
class FormularioCuotaSheet extends StatefulWidget {
  final String organizacionId;
  final String paradaId;
  final String registradoPor;
  final Future<List<ConductorItem>> conductoresFuture;
  final ParadaDetalleService service;
  const FormularioCuotaSheet({
    super.key,
    required this.organizacionId,
    required this.paradaId,
    required this.registradoPor,
    required this.conductoresFuture,
    required this.service,
  });

  @override
  State<FormularioCuotaSheet> createState() => _FormularioCuotaSheetState();
}

class _FormularioCuotaSheetState extends State<FormularioCuotaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _montoAdicionalController = TextEditingController();
  final _motivoController = TextEditingController(text: 'Pago mensual');
  ConductorItem? _conductor;
  late int _mes;
  late int _anio;
  late DateTime _fechaVencimiento;
  late DateTime _fechaLimite;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _mes = hoy.month;
    _anio = hoy.year;
    _fechaVencimiento = DateTime(hoy.year, hoy.month + 1, 0); // último día del mes
    _fechaLimite = _fechaVencimiento.add(const Duration(days: 10));
  }

  @override
  void dispose() {
    _montoController.dispose();
    _montoAdicionalController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha({required bool esVencimiento}) async {
    final actual = esVencimiento ? _fechaVencimiento : _fechaLimite;
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(actual.year - 1),
      lastDate: DateTime(actual.year + 2),
    );
    if (elegida == null) return;
    setState(() {
      if (esVencimiento) {
        _fechaVencimiento = elegida;
      } else {
        _fechaLimite = elegida;
      }
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_conductor == null) {
      setState(() => _error = 'Elegí un conductor.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.crearCuota(
        organizacionId: widget.organizacionId,
        usuarioId: _conductor!.usuarioId,
        paradaId: widget.paradaId,
        mes: _mes,
        anio: _anio,
        montoBase: double.parse(_montoController.text.replaceAll(',', '.')),
        montoAdicional: _montoAdicionalController.text.trim().isEmpty
            ? 0
            : double.parse(_montoAdicionalController.text.replaceAll(',', '.')),
        fechaVencimiento: _fechaVencimiento,
        fechaLimite: _fechaLimite,
        registradoPor: widget.registradoPor,
        motivo: _motivoController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CuotaException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar el pago. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
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
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Registrar pago', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Cargá un pago para un conductor de esta parada.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<ConductorItem>>(
                future: widget.conductoresFuture,
                builder: (context, snapshot) {
                  final conductores = snapshot.data ?? [];
                  return DropdownButtonFormField<ConductorItem>(
                    value: _conductor,
                    decoration:
                        const InputDecoration(labelText: 'Conductor', border: OutlineInputBorder()),
                    items: conductores
                        .map((c) => DropdownMenuItem(value: c, child: Text(c.nombre)))
                        .toList(),
                    onChanged: (valor) => setState(() => _conductor = valor),
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo del pago',
                  helperText: 'Ej: Pago mensual, Multa, Evento especial...',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Ingresá el motivo';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _mes,
                      decoration: const InputDecoration(labelText: 'Mes', border: OutlineInputBorder()),
                      items: List.generate(12, (i) => i + 1)
                          .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                          .toList(),
                      onChanged: (valor) {
                        if (valor != null) setState(() => _mes = valor);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: '$_anio',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Año', border: OutlineInputBorder()),
                      onChanged: (valor) {
                        final n = int.tryParse(valor);
                        if (n != null) _anio = n;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _montoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Ingresá el monto';
                  return double.tryParse(value.replaceAll(',', '.')) == null ? 'Monto inválido' : null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _montoAdicionalController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto adicional (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _elegirFecha(esVencimiento: true),
                      child: Text('Vence: ${formatoFecha.format(_fechaVencimiento)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _elegirFecha(esVencimiento: false),
                      child: Text('Límite: ${formatoFecha.format(_fechaLimite)}'),
                    ),
                  ),
                ],
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
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar pago'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cambio manual de estado de una cuota ya cargada (ej. registrar un
/// pago en efectivo, o exonerar).
class CambiarEstadoCuotaSheet extends StatefulWidget {
  final CuotaItem cuota;
  final ParadaDetalleService service;
  const CambiarEstadoCuotaSheet({super.key, required this.cuota, required this.service});

  @override
  State<CambiarEstadoCuotaSheet> createState() => _CambiarEstadoCuotaSheetState();
}

class _CambiarEstadoCuotaSheetState extends State<CambiarEstadoCuotaSheet> {
  bool _guardando = false;
  String? _error;

  static const _opciones = {
    'pendiente': 'Pendiente',
    'pagado': 'Pagado',
    'atrasado': 'Atrasado',
    'exonerado': 'Exonerado',
  };

  Future<void> _elegir(String estado) async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.cambiarEstadoCuota(cuotaId: widget.cuota.id, estado: estado);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CuotaException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo actualizar. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.cuota.usuarioNombre} · ${widget.cuota.mes}/${widget.cuota.anio}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              widget.cuota.motivo,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Cambiar estado del pago',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_guardando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._opciones.entries.map((entry) => ListTile(
                    title: Text(entry.value),
                    trailing: widget.cuota.estado == entry.key
                        ? const Icon(Icons.check, color: AppTheme.rojoInstitucional)
                        : null,
                    onTap: () => _elegir(entry.key),
                  )),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
