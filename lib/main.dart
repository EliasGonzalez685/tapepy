import 'package:flutter/material.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.init();
  // TODO: inicializar Firebase (firebase_core) y FCM una vez que
  // Elias tenga el proyecto Firebase creado y los archivos
  // google-services.json / GoogleService-Info.plist agregados.
  runApp(const TapePyApp());
}

class TapePyApp extends StatelessWidget {
  const TapePyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TapePy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRouter.welcome,
      routes: AppRouter.routes,
    );
  }
}
