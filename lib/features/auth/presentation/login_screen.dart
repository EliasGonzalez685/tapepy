import 'package:flutter/material.dart';
import '../data/auth_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/organizacion_branding.dart';

class LoginScreen extends StatefulWidget {
  // Organización elegida en la pantalla anterior (selección de
  // organización). Puede venir null si se llega acá por otra vía (ej.
  // deep link) — en ese caso se muestra solo el logo de TapePy, sin
  // asumir ninguna organización puntual.
  final OrganizacionBranding? organizacion;

  const LoginScreen({super.key, this.organizacion});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identificadorController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _identificadorController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _mostrarOlvidasteContrasena() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Olvidaste tu contraseña?'),
        content: const Text(
          'Contactá al presidente de tu asociación o al responsable de la '
          'plataforma para que te ayuden a restablecerla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final usuario = await _authService.signIn(
        identificador: _identificadorController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        AppRouter.homeRouteFor(usuario.rol),
        arguments: usuario,
      );
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final organizacion = widget.organizacion;
    final colorAcento = organizacion?.colorPrimario ?? AppTheme.rojoInstitucional;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // TapePy (plataforma) + logo de la organización elegida,
                    // uno al lado del otro — deja claro con qué cuenta se
                    // está entrando. Si no se sabe la organización (llegó
                    // por otra vía), se muestra solo el de TapePy.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/images/tapepy_logo_blanco.png',
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (organizacion != null) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.close,
                                size: 20, color: Colors.grey),
                          ),
                          ClipOval(
                            child: Image.asset(
                              organizacion.logoAsset,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      organizacion != null
                          ? 'Bienvenido a ${organizacion.nombre}'
                          : 'Ingresá a tu cuenta',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    Icon(
                      Icons.badge_outlined,
                      size: 72,
                      color: colorAcento.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _identificadorController,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Cédula o email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresá tu cédula o email';
                        }
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
                        if (value == null || value.isEmpty) {
                          return 'Ingresá tu contraseña';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : _mostrarOlvidasteContrasena,
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(backgroundColor: colorAcento),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Ingresar'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).pushNamed(
                                AppRouter.registro,
                                arguments: widget.organizacion,
                              ),
                      child: const Text('¿No tenés cuenta? Registrate'),
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
