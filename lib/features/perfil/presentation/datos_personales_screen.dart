import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart' show Usuario, tallasRemeraDisponibles;
import '../../../shared/models/user_role.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/perfil_service.dart';
import 'cambiar_contrasena_screen.dart';

/// Datos personales del usuario logueado: nombre, teléfono, cédula y
/// N° de socio se pueden editar acá mismo (vale para cualquier rol:
/// conductor, presidente de parada o de asociación — ver
/// PerfilService.actualizarDatosPersonales). Solo el email queda fuera,
/// por estar atado a la cuenta de Supabase Auth. La foto se sube/cambia
/// desde acá también.
class DatosPersonalesScreen extends StatefulWidget {
  final Usuario usuario;
  const DatosPersonalesScreen({super.key, required this.usuario});

  @override
  State<DatosPersonalesScreen> createState() => _DatosPersonalesScreenState();
}

class _DatosPersonalesScreenState extends State<DatosPersonalesScreen> {
  final _perfilService = PerfilService();
  final _picker = ImagePicker();
  bool _subiendo = false;
  bool _guardandoTalla = false;
  String? _fotoUrl;
  String? _tallaRemera;
  late String _nombre;
  String? _telefono;
  String? _cedula;
  String? _numeroSocio;

  @override
  void initState() {
    super.initState();
    _fotoUrl = widget.usuario.fotoPerfilUrl;
    _tallaRemera = widget.usuario.tallaRemera;
    _nombre = widget.usuario.nombre;
    _telefono = widget.usuario.telefono;
    _cedula = widget.usuario.cedula;
    _numeroSocio = widget.usuario.numeroSocio;
  }

  Future<void> _editarDatos() async {
    final resultado = await showModalBottomSheet<_DatosEditados>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditarDatosSheet(
        nombre: _nombre,
        telefono: _telefono,
        cedula: _cedula,
        numeroSocio: _numeroSocio,
      ),
    );
    if (resultado == null) return;

    final anteriores = _DatosEditados(
      nombre: _nombre,
      telefono: _telefono,
      cedula: _cedula,
      numeroSocio: _numeroSocio,
    );
    setState(() {
      _nombre = resultado.nombre;
      _telefono = resultado.telefono;
      _cedula = resultado.cedula;
      _numeroSocio = resultado.numeroSocio;
    });
    try {
      await _perfilService.actualizarDatosPersonales(
        usuarioId: widget.usuario.id,
        nombre: resultado.nombre,
        telefono: resultado.telefono,
        cedula: resultado.cedula,
        numeroSocio: resultado.numeroSocio,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Datos actualizados')));
    } on PerfilException catch (e) {
      if (!mounted) return;
      setState(() {
        _nombre = anteriores.nombre;
        _telefono = anteriores.telefono;
        _cedula = anteriores.cedula;
        _numeroSocio = anteriores.numeroSocio;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _guardarTalla(String talla) async {
    final anterior = _tallaRemera;
    setState(() {
      _tallaRemera = talla;
      _guardandoTalla = true;
    });
    try {
      await _perfilService.actualizarTallaRemera(
        usuarioId: widget.usuario.id,
        tallaRemera: talla,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _tallaRemera = anterior);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la talla. Intentá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _guardandoTalla = false);
    }
  }

  Future<void> _elegirYSubirFoto() async {
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (origen == null) return;

    final archivo = await _picker.pickImage(
      source: origen,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (archivo == null) return;

    setState(() => _subiendo = true);
    try {
      final bytes = await archivo.readAsBytes();
      final url = await _perfilService.subirFotoPerfil(
        usuarioId: widget.usuario.id,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _fotoUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo subir la foto. Intentá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuario = widget.usuario;
    final inicial = usuario.nombre.trim().isNotEmpty
        ? usuario.nombre.trim()[0].toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos personales'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar mis datos',
            onPressed: _editarDatos,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: AppTheme.rojoInstitucional,
                      backgroundImage: _fotoUrl != null ? NetworkImage(_fotoUrl!) : null,
                      child: _fotoUrl == null
                          ? Text(
                              inicial,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: GestureDetector(
                        onTap: _subiendo ? null : _elegirYSubirFoto,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.rojoInstitucional,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: _subiendo
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_nombre,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  usuario.rol.label,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Card(
            child: Column(
              children: [
                _CampoInfo(icono: Icons.email_outlined, etiqueta: 'Email', valor: usuario.email),
                const Divider(height: 1),
                _CampoInfo(icono: Icons.phone_outlined, etiqueta: 'Teléfono', valor: _telefono),
                const Divider(height: 1),
                _CampoInfo(icono: Icons.badge_outlined, etiqueta: 'Cédula', valor: _cedula),
                const Divider(height: 1),
                _CampoInfo(
                    icono: Icons.confirmation_number_outlined,
                    etiqueta: 'N° de socio',
                    valor: _numeroSocio),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ListTile(
                leading: const IconBadge(
                  icono: Icons.checkroom_outlined,
                  color: AppTheme.rojoInstitucional,
                  diametro: 40,
                ),
                title: const Text('Talla de remera'),
                subtitle: Text(_tallaRemera ?? 'No completada'),
                trailing: _guardandoTalla
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : DropdownButton<String>(
                        value: _tallaRemera,
                        hint: const Text('Elegir'),
                        underline: const SizedBox.shrink(),
                        items: tallasRemeraDisponibles
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (talla) {
                          if (talla != null) _guardarTalla(talla);
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const IconBadge(
                icono: Icons.lock_outline,
                color: AppTheme.rojoInstitucional,
                diametro: 40,
              ),
              title: const Text('Cambiar contraseña'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CambiarContrasenaScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoInfo extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String? valor;
  const _CampoInfo({required this.icono, required this.etiqueta, this.valor});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icono, color: Theme.of(context).colorScheme.outline),
      title: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(
        (valor == null || valor!.isEmpty) ? 'No registrado' : valor!,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _DatosEditados {
  final String nombre;
  final String? telefono;
  final String? cedula;
  final String? numeroSocio;
  const _DatosEditados({required this.nombre, this.telefono, this.cedula, this.numeroSocio});
}

/// Formulario para editar nombre, teléfono, cédula y N° de socio —
/// disponible para cualquier rol. Email no se toca acá (ver
/// PerfilService.actualizarDatosPersonales).
class _EditarDatosSheet extends StatefulWidget {
  final String nombre;
  final String? telefono;
  final String? cedula;
  final String? numeroSocio;
  const _EditarDatosSheet({
    required this.nombre,
    this.telefono,
    this.cedula,
    this.numeroSocio,
  });

  @override
  State<_EditarDatosSheet> createState() => _EditarDatosSheetState();
}

class _EditarDatosSheetState extends State<_EditarDatosSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nombreController = TextEditingController(text: widget.nombre);
  late final _telefonoController = TextEditingController(text: widget.telefono ?? '');
  late final _cedulaController = TextEditingController(text: widget.cedula ?? '');
  late final _numeroSocioController = TextEditingController(text: widget.numeroSocio ?? '');

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _cedulaController.dispose();
    _numeroSocioController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_DatosEditados(
      nombre: _nombreController.text.trim(),
      telefono: _telefonoController.text,
      cedula: _cedulaController.text,
      numeroSocio: _numeroSocioController.text,
    ));
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Editar mis datos',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombreController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Ingresá tu nombre' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _telefonoController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cedulaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cédula',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _numeroSocioController,
              decoration: const InputDecoration(
                labelText: 'N° de socio',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardar,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
