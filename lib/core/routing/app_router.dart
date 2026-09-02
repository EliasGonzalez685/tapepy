import 'package:flutter/material.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/onboarding/presentation/organizacion_select_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/registro_screen.dart';
import '../../features/conductor/presentation/conductor_home_screen.dart';
import '../../features/parada/presentation/parada_home_screen.dart';
import '../../features/asociacion/presentation/asociacion_home_screen.dart';
import '../../features/superadmin/presentation/superadmin_home_screen.dart';
import '../../features/plataforma/presentation/dueno_plataforma_home_screen.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/usuario.dart';
import '../../shared/models/organizacion_branding.dart';

/// Rutas nombradas. A medida que se sumen pantallas del wireframe
/// (13 pantallas ya diseñadas) se van agregando acá por rol.
///
/// Flujo de entrada: welcome (marca TapePy) -> organizacionSelect
/// (elegir cliente, hoy solo Traude) -> login (email/contraseña, más
/// adelante también cédula) -> home según rol.
class AppRouter {
  static const welcome = '/';
  static const organizacionSelect = '/organizaciones';
  static const login = '/login';
  static const registro = '/registro';
  static const conductorHome = '/conductor';
  static const paradaHome = '/parada';
  static const asociacionHome = '/asociacion';
  static const superadminHome = '/superadmin';
  static const plataformaHome = '/plataforma';

  static Map<String, WidgetBuilder> routes = {
    welcome: (_) => const WelcomeScreen(),
    organizacionSelect: (_) => const OrganizacionSelectScreen(),
    login: (context) => LoginScreen(
          organizacion: ModalRoute.of(context)!.settings.arguments
              as OrganizacionBranding?,
        ),
    registro: (_) => const RegistroScreen(),
    conductorHome: (context) => ConductorHomeScreen(
          usuario: ModalRoute.of(context)!.settings.arguments as Usuario?,
        ),
    paradaHome: (context) => ParadaHomeScreen(
          usuario: ModalRoute.of(context)!.settings.arguments as Usuario?,
        ),
    asociacionHome: (context) => AsociacionHomeScreen(
          usuario: ModalRoute.of(context)!.settings.arguments as Usuario?,
        ),
    superadminHome: (_) => const SuperadminHomeScreen(),
    plataformaHome: (context) => DuenoPlataformaHomeScreen(
          usuario: ModalRoute.of(context)!.settings.arguments as Usuario?,
        ),
  };

  /// A qué home va cada rol después de loguearse.
  static String homeRouteFor(UserRole rol) {
    switch (rol) {
      case UserRole.duenoPlataforma:
        return plataformaHome;
      case UserRole.superadmin:
        return superadminHome;
      case UserRole.presidenteAsociacion:
        return asociacionHome;
      case UserRole.presidenteParada:
        return paradaHome;
      case UserRole.conductor:
        return conductorHome;
    }
  }
}
