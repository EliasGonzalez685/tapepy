import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/registro_service.dart';
import '../data/lote_pago_service.dart';
import '../data/parada_detalle_service.dart' show ConductorItem;

/// Generar un pago grupal ("a todos") — con la misma idea para los dos
/// roles que lo usan, cada uno acotado a lo suyo:
/// - Presidente de asociación: elige, con checkboxes, cualquier
///   subconjunto de PARADAS de la organización (una, varias, o todas
///   con el botón "Todas").
/// - Presidente de parada: su alcance sigue siendo solo su propia
///   parada (no puede tocar otras), pero dentro de ella elige, con
///   checkboxes, a qué SOCIOS puntuales les llega el pago — puede
///   excluir a algunos si hace falta.
/// Al guardar, el pago le aparece a cada socio elegido como una cuota
/// individual pendiente.
class FormularioLotePagoSheet extends StatefulWidget {
  final String organizacionId;
  final String creadoPor;
  final LotePagoService service;

  /// true = presidente de asociación (elige paradas). false =
  /// presidente de parada (alcance fijo a su parada, elige conductores
  /// dentro de ella).
  final bool esPresidenteAsociacion;

  /// Requeridos cuando [esPresidenteAsociacion] es false.
  final String? paradaIdFija;
  final String? paradaNombreFija;
  final Future<List<ConductorItem>>? conductoresFuture;

  /// Cuando [esPresidenteAsociacion] es true y se abre este formulario
  /// desde el detalle de una parada puntual, preselecciona esa parada
  /// en el selector de alcance en vez de "Todas las paradas".
  final String? alcanceInicialId;

  const FormularioLotePagoSheet({
    super.key,
    required this.organizacionId,
    required this.creadoPor,
    required this.service,
    required this.esPresidenteAsociacion,
    this.paradaIdFija,
    this.paradaNombreFija,
    this.conductoresFuture,
    this.alcanceInicialId,
  });

  @override
  State<FormularioLotePagoSheet> createState() => _FormularioLotePagoSheetState();
}

class _FormularioLotePagoSheetState extends State<FormularioLotePagoSheet> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _montoAdicionalController = TextEditingController();
  final _motivoController = TextEditingController();
  final _registroService = RegistroService();

  late Future<List<ParadaOpcion>> _futureParadas;
  final Set<String> _seleccionadas = {};

  // Solo se usa cuando !esPresidenteAsociacion: qué socios puntuales de
  // su parada quedan incluidos. Arranca vacío y se completa con todos
  // apenas carga la lista (_conductoresInicializados evita pisar una
  // deselección manual si el future se resuelve más de una vez).
  final Set<String> _conductoresSeleccionados = {};
  bool _conductoresInicializados = false;

  late int _mes;
  late int _anio;
  late DateTime _fechaVencimiento;
  late DateTime _fechaLimite;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.esPresidenteAsociacion) {
      _futureParadas = _registroService.cargarParadas(widget.organizacionId);
      if (widget.alcanceInicialId != null) _seleccionadas.add(widget.alcanceInicialId!);
    } else {
      _seleccionadas.add(widget.paradaIdFija!);
      widget.conductoresFuture?.then((lista) {
        if (_conductoresInicializados || !mounted) return;
        setState(() {
          _conductoresInicializados = true;
          _conductoresSeleccionados.addAll(lista.map((c) => c.usuarioId));
        });
      });
    }
    final hoy = DateTime.now();
    _mes = hoy.month;
    _anio = hoy.year;
    _fechaVencimiento = DateTime(hoy.year, hoy.month + 1, 0);
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
    if (widget.esPresidenteAsociacion) {
      if (_seleccionadas.isEmpty) {
        setState(() => _error = 'Elegí al menos una parada.');
        return;
      }
    } else {
      if (!_conductoresInicializados) {
        setState(() => _error = 'Esperá a que carguen los socios de la parada.');
        return;
      }
      if (_conductoresSeleccionados.isEmpty) {
        setState(() => _error = 'Elegí al menos un socio.');
        return;
      }
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.crearLotePago(
        organizacionId: widget.organizacionId,
        paradaIds: _seleccionadas.toList(),
        usuarioIds: widget.esPresidenteAsociacion ? null : _conductoresSeleccionados.toList(),
        motivo: _motivoController.text.trim(),
        montoBase: double.parse(_montoController.text.replaceAll(',', '.')),
        montoAdicional: _montoAdicionalController.text.trim().isEmpty
            ? 0
            : double.parse(_montoAdicionalController.text.replaceAll(',', '.')),
        mes: _mes,
        anio: _anio,
        fechaVencimiento: _fechaVencimiento,
        fechaLimite: _fechaLimite,
        creadoPor: widget.creadoPor,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on LotePagoException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo generar el pago grupal. Intentá de nuevo.');
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
              Text('Generar pago a todos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Este pago le va a aparecer como pendiente a cada socio del alcance elegido.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (widget.esPresidenteAsociacion)
                FutureBuilder<List<ParadaOpcion>>(
                  future: _futureParadas,
                  builder: (context, snapshot) {
                    final paradas = snapshot.data ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Paradas (${_seleccionadas.length} de ${paradas.length})',
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ),
                            TextButton(
                              onPressed: paradas.isEmpty
                                  ? null
                                  : () => setState(
                                      () => _seleccionadas..addAll(paradas.map((p) => p.id))),
                              child: const Text('Todas'),
                            ),
                            TextButton(
                              onPressed: _seleccionadas.isEmpty
                                  ? null
                                  : () => setState(_seleccionadas.clear),
                              child: const Text('Ninguna'),
                            ),
                          ],
                        ),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: snapshot.connectionState == ConnectionState.waiting
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                )
                              : paradas.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('No hay paradas cargadas todavía.'),
                                    )
                                  : ListView(
                                      shrinkWrap: true,
                                      children: paradas
                                          .map((p) => CheckboxListTile(
                                                dense: true,
                                                value: _seleccionadas.contains(p.id),
                                                title: Text(p.nombre),
                                                onChanged: (marcado) => setState(() {
                                                  if (marcado == true) {
                                                    _seleccionadas.add(p.id);
                                                  } else {
                                                    _seleccionadas.remove(p.id);
                                                  }
                                                }),
                                              ))
                                          .toList(),
                                    ),
                        ),
                      ],
                    );
                  },
                )
              else ...[
                Text(widget.paradaNombreFija ?? 'Mi parada',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                FutureBuilder<List<ConductorItem>>(
                  future: widget.conductoresFuture,
                  builder: (context, snapshot) {
                    final conductores = snapshot.data ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                  'Socios (${_conductoresSeleccionados.length} de ${conductores.length})',
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ),
                            TextButton(
                              onPressed: conductores.isEmpty
                                  ? null
                                  : () => setState(() => _conductoresSeleccionados
                                      ..addAll(conductores.map((c) => c.usuarioId))),
                              child: const Text('Todos'),
                            ),
                            TextButton(
                              onPressed: _conductoresSeleccionados.isEmpty
                                  ? null
                                  : () => setState(_conductoresSeleccionados.clear),
                              child: const Text('Ninguno'),
                            ),
                          ],
                        ),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: snapshot.connectionState == ConnectionState.waiting
                              ? const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                )
                              : conductores.isEmpty
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('No hay socios cargados todavía en esta parada.'),
                                    )
                                  : ListView(
                                      shrinkWrap: true,
                                      children: conductores
                                          .map((c) => CheckboxListTile(
                                                dense: true,
                                                value: _conductoresSeleccionados.contains(c.usuarioId),
                                                title: Text(c.nombre),
                                                onChanged: (marcado) => setState(() {
                                                  if (marcado == true) {
                                                    _conductoresSeleccionados.add(c.usuarioId);
                                                  } else {
                                                    _conductoresSeleccionados.remove(c.usuarioId);
                                                  }
                                                }),
                                              ))
                                          .toList(),
                                    ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo del pago',
                  helperText: 'Ej: Pago mensual a la app, Pago extraordinario...',
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
                    : const Text('Generar pago a todos'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
