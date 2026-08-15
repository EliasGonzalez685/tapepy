import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/models/usuario.dart';

const _emailResponsablePlataforma = 'eliasgonzalez685@gmail.com';

/// "Para escribirle o tratar con el responsable de la plataforma o con
/// el presidente de la asociación" — punto de contacto único, igual
/// para cualquier rol.
class CentroAyudaScreen extends StatefulWidget {
  final Usuario usuario;
  const CentroAyudaScreen({super.key, required this.usuario});

  @override
  State<CentroAyudaScreen> createState() => _CentroAyudaScreenState();
}

class _CentroAyudaScreenState extends State<CentroAyudaScreen> {
  final _service = OrganizacionService();
  Future<ContactoPresidente?>? _future;

  @override
  void initState() {
    super.initState();
    final orgId = widget.usuario.organizacionId;
    // El presidente de asociación no necesita que le muestren su
    // propio contacto como si fuera otra persona.
    if (orgId != null && widget.usuario.rol != UserRole.presidenteAsociacion) {
      _future = _service.cargarPresidenteAsociacion(orgId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centro de ayuda')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Para escribirle o tratar cualquier consulta, podés contactar al '
            'responsable de la plataforma o al presidente de tu asociación.',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 20),
          _TarjetaContacto(
            icono: Icons.build_outlined,
            titulo: 'Responsable de la plataforma',
            subtitulo: 'TapePy — soporte técnico',
            email: _emailResponsablePlataforma,
          ),
          if (_future != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<ContactoPresidente?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final contacto = snapshot.data;
                if (contacto == null) {
                  return Text(
                    'Tu organización todavía no tiene un presidente de asociación asignado.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  );
                }
                return _TarjetaContacto(
                  icono: Icons.person_outline,
                  titulo: 'Presidente de tu asociación',
                  subtitulo: contacto.nombre,
                  email: contacto.email,
                  telefono: contacto.telefono,
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaContacto extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final String? email;
  final String? telefono;

  const _TarjetaContacto({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    this.email,
    this.telefono,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.rojoInstitucional.withValues(alpha: 0.12),
              child: Icon(icono, color: AppTheme.rojoInstitucional),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitulo,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (email != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(email!)),
                      ],
                    ),
                  ],
                  if (telefono != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.phone_outlined, size: 16),
                        const SizedBox(width: 6),
                        Text(telefono!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
