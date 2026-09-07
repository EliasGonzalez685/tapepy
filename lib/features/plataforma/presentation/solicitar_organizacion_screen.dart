import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/tipo_organizacion.dart';
import '../data/solicitud_organizacion_service.dart';

/// Pantalla pública (no requiere sesión) para pedir que se sume una
/// organización nueva a la plataforma -- pensada para que Elias pueda
/// ofrecer TapePy a un cliente potencial y mostrarle en el momento que
/// se puede dar de alta, sin depender de programar nada. El pedido le
/// llega al dueño de plataforma como una solicitud pendiente para
/// aceptar o rechazar (ver SolicitudesOrganizacionScreen).
///
/// Se llega acá desde OrganizacionSelectScreen ("¿Tu organización no
/// está?"), que ya trae elegido un rubro -- se usa como valor inicial
/// del selector, pero queda editable por si se equivocó de pantalla.
class SolicitarOrganizacionScreen extends StatefulWidget {
  final TipoOrganizacion tipoInicial;

  const SolicitarOrganizacionScreen({super.key, required this.tipoInicial});

  @override
  State<SolicitarOrganizacionScreen> createState() =>
      _SolicitarOrganizacionScreenState();
}

class _SolicitarOrganizacionScreenState
    extends State<SolicitarOrganizacionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = SolicitudOrganizacionService();

  final _nombreController = TextEditingController();
  final _presidenteController = TextEditingController();
  late TipoOrganizacion _tipo;

  bool _loading = false;
  bool _enviado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tipo = widget.tipoInicial;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _presidenteController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.enviarSolicitud(
        nombreOrganizacion: _nombreController.text,
        tipo: _tipo,
        nombrePresidente: _presidenteController.text,
      );
      if (!mounted) return;
      setState(() => _enviado = true);
    } on SolicitudOrganizacionException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo enviar la solicitud. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solicitar organización')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _enviado ? _MensajeEnviado(nombre: _nombreController.text) : _formulario(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formulario() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sumá tu organización',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Completá estos datos y le llega al dueño de la plataforma para '
            'su aprobación. Una vez aprobada, la organización ya queda '
            'disponible para que su presidente cree su cuenta.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nombreController,
            decoration: const InputDecoration(
              labelText: 'Nombre de la organización',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Ingresá el nombre' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TipoOrganizacion>(
            value: _tipo,
            decoration: const InputDecoration(
              labelText: 'Rubro',
              border: OutlineInputBorder(),
            ),
            items: TipoOrganizacion.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _tipo = value);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _presidenteController,
            decoration: const InputDecoration(
              labelText: 'Nombre del presidente de asociación',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Ingresá el nombre del presidente' : null,
            onFieldSubmitted: (_) => _enviar(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _enviar,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
  }
}

class _MensajeEnviado extends StatelessWidget {
  final String nombre;
  const _MensajeEnviado({required this.nombre});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Icon(Icons.hourglass_top_outlined, size: 56, color: AppTheme.rojoInstitucional),
        const SizedBox(height: 20),
        Text(
          'Solicitud enviada',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Esperando confirmación del dueño de la plataforma para dar de '
          'alta "$nombre". Te vamos a avisar apenas esté lista.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 28),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver'),
        ),
      ],
    );
  }
}
