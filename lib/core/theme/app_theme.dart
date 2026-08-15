import 'package:flutter/material.dart';

/// Tema base de la app. Rojo institucional (#8B0000) como color
/// prioritario/de acento, definido por Elias el 2026-08-04.
class AppTheme {
  static const Color rojoInstitucional = Color(0xFF8B0000);

  // Semáforo de estado (paradas, documentos, cuotas)
  static const Color estadoOk = Color(0xFF2E7D32); // verde
  static const Color estadoAtencion = Color(0xFFF9A825); // amarillo
  static const Color estadoUrgente = rojoInstitucional; // rojo

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: rojoInstitucional,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFFAF8F7),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      // Cards tipo "flotante": sombra suave en vez de borde, sin líneas
      // duras — más parecido a apps de servicios pulidas (referencia UX
      // de Elias, 2026-08-04) que al estilo "formulario" con bordes.
      cardTheme: CardThemeData(
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: rojoInstitucional,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
