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
  /// Apunta a la páginita estática de Traude Web en GitHub Pages
  /// (repo aparte: github.com/EliasGonzalez685/traude-web,
  /// verificar-carnet.html), NO directo a la Edge Function
  /// `verificar-carnet` -- el dominio *.supabase.co fuerza el
  /// Content-Type de las Edge Functions a text/plain (limitación de la
  /// plataforma, ver comentario en esa función), así que un link
  /// directo mostraría el HTML como texto plano en vez de renderizarlo.
  /// La página de GitHub Pages le pide los datos a esa función por
  /// fetch() y sí los renderiza bien.
  ///
  /// Antes apuntaba a eliasgonzalez685.github.io/tapepy/ (repo de la
  /// app) -- era momentáneo, según lo dicho por Elias, hasta tener el
  /// sitio de Traude Web listo y publicado. Cambiado el 2026-08-25.
  static String urlVerificacionCarnet(String qrToken) =>
      'https://eliasgonzalez685.github.io/traude-web/verificar-carnet.html?token=$qrToken';
}
