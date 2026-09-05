import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Inicializa Supabase leyendo la URL y anon key desde el .env
/// (ver .env.example). Nunca hardcodear las claves acá.
class SupabaseConfig {
  static Future<void> init() async {
    await dotenv.load(fileName: '.env');

    final url = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (url == null || anonKey == null) {
      throw Exception(
        'Falta SUPABASE_URL o SUPABASE_ANON_KEY en el archivo .env. '
        'Copiá .env.example a .env y completá con los datos de tu proyecto.',
      );
    }

    await Supabase.initialize(url: url, anonKey: anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// URL pública de verificación de carnet: es lo que codifica el QR
  /// del carnet digital, para que cualquier lector de QR del teléfono
  /// la abra directo, sin necesidad de tener la app instalada.
  ///
  /// Apunta a la páginita estática de Traude Web, deployada en Vercel
  /// (mismo repo: github.com/EliasGonzalez685/traude-web,
  /// verificar-carnet.html), NO directo a la Edge Function
  /// `verificar-carnet` -- el dominio *.supabase.co fuerza el
  /// Content-Type de las Edge Functions a text/plain (limitación de la
  /// plataforma, ver comentario en esa función), así que un link
  /// directo mostraría el HTML como texto plano en vez de renderizarlo.
  /// La página deployada le pide los datos a esa función por fetch()
  /// y sí los renderiza bien.
  ///
  /// URL de Vercel (traude-tour.vercel.app) elegida por Elias en vez de
  /// GitHub Pages porque no quería que su usuario personal
  /// (eliasgonzalez685) apareciera en la URL que ve el cliente. Es un
  /// dominio .vercel.app gratuito, momentáneo, hasta que se compre un
  /// dominio propio para el sitio -- cuando eso pase, actualizar esta
  /// constante de nuevo. Cambiado el 2026-08-25 (antes apuntaba a
  /// eliasgonzalez685.github.io/traude-web/, y antes de eso a
  /// eliasgonzalez685.github.io/tapepy/).
  ///
  /// A partir de 2026-09-05 esto es org-aware: cada organización puede
  /// tener su propia página de verificación (columna
  /// `organizaciones.url_verificacion_carnet`, ver
  /// OrganizacionBranding.urlVerificacionCarnet). [baseUrl] es esa URL,
  /// pasada por el llamador desde datos.organizacion; si viene null
  /// (organización sin sitio propio todavía) se cae a la de Traude,
  /// que sigue siendo el fallback histórico.
  static String urlVerificacionCarnet(String qrToken, {String? baseUrl}) =>
      '${baseUrl ?? 'https://traude-tour.vercel.app/verificar-carnet.html'}?token=$qrToken';
}
