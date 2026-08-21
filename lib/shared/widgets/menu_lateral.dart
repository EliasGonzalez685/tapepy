import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../features/perfil/presentation/cambiar_contrasena_screen.dart';
import '../../features/perfil/presentation/carnet_screen.dart';
import '../../features/perfil/presentation/datos_personales_screen.dart';
import '../../features/perfil/presentation/mi_qr_screen.dart';
import '../../features/conductor/presentation/mi_constancia_screen.dart';
import '../../features/mensajeria/presentation/mensajeria_screen.dart';
import '../../features/ayuda/presentation/info_aplicacion_screen.dart';
import '../../features/ayuda/presentation/comentarios_screen.dart';
import '../../features/ayuda/presentation/condiciones_privacidad_screen.dart';
import '../../features/ayuda/presentation/centro_ayuda_screen.dart';
import '../../features/plataforma/presentation/mi_cuota_plataforma_screen.dart';
import '../models/user_role.dart';
import '../models/usuario.dart';

/// Barra lateral vertical reutilizable por todos los roles: datos
/// personales, cambio de contraseña, mensajería, carnet y QR son comunes
/// a cualquier usuario. Cada pantalla home puede sumar sus propios ítems
/// (ej. "Presidentes de parada" solo para el presidente de asociación)
/// vía [itemsExtra].
class MenuLateral extends StatelessWidget {
  final Usuario? usuario;
  final Future<int> noLeidosFuture;
  final VoidCallback onCerrarSesion;
  final List<Widget> itemsExtra;

  const MenuLateral({
    super.key,
    required this.usuario,
    required this.noLeidosFuture,
    required this.onCerrarSesion,
    this.itemsExtra = const [],
  });

  @override
  Widget build(BuildContext context) {
    final nombre = usuario?.nombre ?? 'Usuario';
    final inicial = nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : '?';

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.rojoInstitucional, Color(0xFF6B0000)],
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        usuario?.fotoPerfilUrl != null ? NetworkImage(usuario!.fotoPerfilUrl!) : null,
                    child: usuario?.fotoPerfilUrl == null
                        ? Text(
                            inicial,
                            style: const TextStyle(
                              color: AppTheme.rojoInstitucional,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          usuario?.rol.label ?? '',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ItemMenuLateral(
                    icono: Icons.person_outline,
                    titulo: 'Datos personales',
                    onTap: () {
                      Navigator.of(context).pop();
                      if (usuario == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => DatosPersonalesScreen(usuario: usuario!)),
                      );
                    },
                  ),
                  ItemMenuLateral(
                    icono: Icons.lock_outline,
                    titulo: 'Cambiar contraseña',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CambiarContrasenaScreen()),
                      );
                    },
                  ),
                  // La mensajería es trabajo interno de cada asociación
                  // (conductores y presidentes hablando entre ellos) —
                  // el dueño de plataforma no participa de esto.
                  if (usuario?.rol != UserRole.duenoPlataforma)
                    FutureBuilder<int>(
                      future: noLeidosFuture,
                      builder: (context, snapshot) {
                        final noLeidos = snapshot.data ?? 0;
                        return ItemMenuLateral(
                          icono: Icons.mail_outline,
                          titulo: 'Mensajería',
                          contador: noLeidos > 0 ? noLeidos : null,
                          onTap: () {
                            Navigator.of(context).pop();
                            if (usuario == null) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => MensajeriaScreen(usuario: usuario!)),
                            );
                          },
                        );
                      },
                    ),
                  // Carnet y QR identifican a alguien que trabaja en el
                  // día a día de la asociación (conductor, presidente de
                  // parada o de asociación) — el dueño de plataforma
                  // supervisa desde afuera, no es miembro de ninguna
                  // asociación puntual, así que no le corresponden.
                  if (usuario?.rol != UserRole.duenoPlataforma) ...[
                    ItemMenuLateral(
                      icono: Icons.badge_outlined,
                      titulo: 'Mi carnet',
                      onTap: () {
                        Navigator.of(context).pop();
                        if (usuario == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => CarnetScreen(usuarioId: usuario!.id)),
                        );
                      },
                    ),
                    ItemMenuLateral(
                      icono: Icons.qr_code,
                      titulo: 'Mi código QR',
                      onTap: () {
                        Navigator.of(context).pop();
                        if (usuario == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => MiQrScreen(usuarioId: usuario!.id)),
                        );
                      },
                    ),
                  ],
                  // Cuota de plataforma: lo que cada persona le paga al
                  // dueño de la plataforma por el servicio de TapePy en
                  // sí (distinto de "Mis pagos", que es interno a la
                  // asociación/parada). Pagan presidente de asociación,
                  // presidente de parada y conductor -- el dueño no se
                  // cobra a sí mismo, y superadmin no es un socio real.
                  if (usuario?.rol != UserRole.duenoPlataforma && usuario?.rol != UserRole.superadmin)
                    ItemMenuLateral(
                      icono: Icons.workspace_premium_outlined,
                      titulo: 'Cuota de plataforma',
                      onTap: () {
                        Navigator.of(context).pop();
                        if (usuario == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => MiCuotaPlataformaScreen(usuario: usuario!)),
                        );
                      },
                    ),
                  // La constancia certifica que alguien es socio
                  // propietario o chofer de una línea de transporte —
                  // solo tiene sentido para el conductor pedirla sobre
                  // sí mismo.
                  if (usuario?.rol == UserRole.conductor)
                    ItemMenuLateral(
                      icono: Icons.description_outlined,
                      titulo: 'Solicitar constancia',
                      onTap: () {
                        Navigator.of(context).pop();
                        if (usuario == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => MiConstanciaScreen(usuario: usuario!)),
                        );
                      },
                    ),
                  if (itemsExtra.isNotEmpty) ...[
                    const Divider(height: 24),
                    ...itemsExtra,
                  ],
                  // Al final de todo: esto es material de consulta, no
                  // funciones del día a día — lo importante (paradas,
                  // listados, etc., que llega vía itemsExtra) va primero.
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Text(
                      'AYUDA Y COMENTARIOS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ItemMenuLateral(
                    icono: Icons.info_outline,
                    titulo: 'Info de la aplicación',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const InfoAplicacionScreen()),
                      );
                    },
                  ),
                  // Este ítem es para que un socio le escriba al dueño
                  // de plataforma — no tiene sentido que el propio
                  // dueño lo vea en su menú.
                  if (usuario?.rol != UserRole.duenoPlataforma)
                    ItemMenuLateral(
                      icono: Icons.chat_bubble_outline,
                      titulo: 'Comentarios para mejorar la app',
                      onTap: () {
                        Navigator.of(context).pop();
                        if (usuario == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ComentariosScreen(usuario: usuario!)),
                        );
                      },
                    ),
                  ItemMenuLateral(
                    icono: Icons.gavel_outlined,
                    titulo: 'Condiciones y Políticas de Privacidad',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CondicionesPrivacidadScreen()),
                      );
                    },
                  ),
                  ItemMenuLateral(
                    icono: Icons.support_agent_outlined,
                    titulo: 'Centro de ayuda',
                    onTap: () {
                      Navigator.of(context).pop();
                      if (usuario == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CentroAyudaScreen(usuario: usuario!)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ItemMenuLateral(
              icono: Icons.logout,
              titulo: 'Cerrar sesión',
              color: AppTheme.estadoUrgente,
              onTap: () {
                Navigator.of(context).pop();
                onCerrarSesion();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class ItemMenuLateral extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final VoidCallback onTap;
  final int? contador;
  final Color? color;

  const ItemMenuLateral({
    super.key,
    required this.icono,
    required this.titulo,
    required this.onTap,
    this.contador,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icono, color: color ?? AppTheme.rojoInstitucional),
      title: Text(titulo, style: TextStyle(color: color)),
      trailing: contador == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.estadoUrgente,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$contador',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
      onTap: onTap,
    );
  }
}
