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

  /// URL pública de verificación de carnet (Edge Function
  /// `verificar-carnet`, sin login): es lo que codifica el QR del
  /// carnet digital, para que cualquier lector de QR del teléfono la
  /// abra directo, sin necesidad de tener la app instalada.
  static String urlVerificacionCarnet(String qrToken) =>
      '${dotenv.env['SUPABASE_URL']}/functions/v1/verificar-carnet?token=$qrToken';
}
