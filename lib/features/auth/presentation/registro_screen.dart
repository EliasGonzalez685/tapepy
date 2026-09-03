import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/organizacion_branding.dart';
import '../data/auth_service.dart';
import '../data/registro_service.dart';

/// Alta pública de un nuevo miembro (conductor). Accesible desde el
/// login con "¿No tenés cuenta? Registrate". El presidente de
/// asociación es la única cuenta que NO se crea por acá.
///
/// La organización ya se eligió en la pantalla anterior (selección de
/// organización -> login), así que llega acá como argumento y no se
/// vuelve a preguntar. La parada NO es obligatoria: el conductor puede
/// crear su cuenta sin elegirla y el presidente de asociación se la
/// asigna después, ya con la cuenta aprobada (ver comentario en
/// [[project_traude_pendientes]] y conductor_service.dart).
class RegistroScreen extends StatefulWidget {
  final OrganizacionBranding? organizacion;

  const RegistroScreen({super.key, this.organizacion});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _registroService = RegistroService();

  final _nombreController = TextEditingController();
  final _cedulaController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();

  // Normalmente viene de widget.organizacion.id. Solo se recurre a
  // resolverla acá si por algún motivo se llegó a esta pantalla sin
  // ese argumento (ej. deep link) — mismo criterio de tolerancia que
  // ya usa LoginScreen con organizacion == null.
  String? _organizacionId;
  List<ParadaOpcion> _paradas = [];
  String? _paradaId;
  bool _cargandoParadas = true;

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmar = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final organizacionId = widget.organizacion?.id;
    if (organizacionId != null) {
      await _cargarParadas(organizacionId);
      return;
    }
    // Sin organización forwarded: fallback silencioso a la primera
    // organización activa, para no dejar la pantalla inutilizable.
    try {
      final organizaciones = await _registroService.cargarOrganizaciones();
      if (!mounted) return;
      if (organizaciones.isEmpty) {
        setState(() {
          _cargandoParadas = false;
          _error = 'No hay organizaciones disponibles todavía.';
        });
        return;
      }
      await _cargarParadas(organizaciones.first.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoParadas = false;
        _error = 'No se pudo cargar la información. Intentá de nuevo.';
      });
    }
  }

  Future<void> _cargarParadas(String organizacionId) async {
    setState(() {
      _organizacionId = organizacionId;
      _cargandoParadas = true;
    });
    try {
      final paradas = await _registroService.cargarParadas(organizacionId);
      if (!mounted) return;
      setState(() => _paradas = paradas);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'No se pudieron cargar las paradas. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _cargandoParadas = false);
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _cedulaController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_organizacionId == null) return;
    if (_passwordController.text != _confirmarController.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _registroService.registrarConductor(
        nombre: _nombreController.text.trim(),
        cedula: _cedulaController.text.trim(),
        telefono: _telefonoController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        organizacionId: _organizacionId!,
        paradaId: _paradaId,
      );

      if (!mounted) return;

      // Ninguna cuenta nueva puede usarse hasta que alguna autoridad de
      // la asociación la apruebe (presidente de parada, de asociación o
      // el dueño de plataforma) — si llegó a abrirse sesión, la
      // cerramos y volvemos al login con el mismo aviso en los dos casos.
      await AuthService().signOut();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cuenta creada'),
          content: const Text(
            'Tu registro quedó pendiente de aprobación de las autoridades de tu asociación. '
            'Te vamos a avisar cuando puedas ingresar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on RegistroException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorAcento = widget.organizacion?.colorPrimario ?? AppTheme.rojoInstitucional;
    return Scaffold(
      appBar: AppBar(title: const Text('Crear mi cuenta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Registrate con tus datos. Si ya sabés a qué parada '
                      'pertenecés podés elegirla ahora, o hacerlo después una vez '
                      'que entres a la app.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      value: _paradaId,
                      decoration: InputDecoration(
                        labelText: 'Parada (opcional)',
                        border: const OutlineInputBorder(),
                        suffixIcon: _cargandoParadas
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              )
                            : null,
                      ),
                      items: _paradas
                          .map((p) => DropdownMenuItem(
                              value: p.id, child: Text(p.nombre)))
                          .toList(),
                      onChanged: _organizacionId == null
                          ? null
                          : (value) => setState(() => _paradaId = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nombreController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'Ingresá tu nombre'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cedulaController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cédula',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'Ingresá tu cédula'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _telefonoController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'Ingresá tu teléfono'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty)
                          return 'Ingresá tu email';
                        if (!value.contains('@')) return 'Email inválido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Ingresá una contraseña';
                        if (value.length < 6) return 'Mínimo 6 caracteres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmarController,
                      obscureText: _obscureConfirmar,
                      decoration: InputDecoration(
                        labelText: 'Confirmar contraseña',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmar
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscureConfirmar = !_obscureConfirmar),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Confirmá tu contraseña'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: colorAcento),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Crear mi cuenta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
