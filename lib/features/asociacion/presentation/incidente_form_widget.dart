import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data/parada_detalle_service.dart';

const _tiposIncidente = {
  'accidente': 'Accidente',
  'mecanico': 'Falla mecánica',
  'conflicto': 'Conflicto',
  'otro': 'Otro',
};

/// Reporte manual de un incidente en una parada. Lo usan tanto el
/// presidente de parada (parada_home_screen.dart) como el presidente de
/// asociación viendo el detalle de una parada (parada_detalle_screen.dart)
/// — por eso vive acá, compartido (mismo criterio que FormularioCuotaSheet).
class FormularioIncidenteSheet extends StatefulWidget {
  final String organizacionId;
  final String paradaId;
  final String reportadoPor;
  final Future<List<ConductorItem>> conductoresFuture;
  final ParadaDetalleService service;
  const FormularioIncidenteSheet({
    super.key,
    required this.organizacionId,
    required this.paradaId,
    required this.reportadoPor,
    required this.conductoresFuture,
    required this.service,
  });

  @override
  State<FormularioIncidenteSheet> createState() => _FormularioIncidenteSheetState();
}

class _FormularioIncidenteSheetState extends State<FormularioIncidenteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  String _tipo = 'otro';
  ConductorItem? _conductor;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.crearIncidente(
        organizacionId: widget.organizacionId,
        paradaId: widget.paradaId,
        conductorId: _conductor?.id,
        reportadoPor: widget.reportadoPor,
        tipo: _tipo,
        descripcion: _descripcionController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on IncidenteException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo reportar el incidente. Intentá de nuevo.');
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
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reportar incidente', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Registrá un incidente ocurrido en esta parada.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: _tiposIncidente.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (valor) {
                  if (valor != null) setState(() => _tipo = valor);
                },
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<ConductorItem>>(
                future: widget.conductoresFuture,
                builder: (context, snapshot) {
                  final conductores = snapshot.data ?? [];
                  return DropdownButtonFormField<ConductorItem?>(
                    value: _conductor,
                    decoration: const InputDecoration(
                      labelText: 'Conductor involucrado (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<ConductorItem?>(value: null, child: Text('Ninguno en particular')),
                      ...conductores
                          .map((c) => DropdownMenuItem<ConductorItem?>(value: c, child: Text(c.nombre))),
                    ],
                    onChanged: (valor) => setState(() => _conductor = valor),
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descripcionController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Contá qué pasó';
                  return null;
                },
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
                    : const Text('Reportar incidente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
