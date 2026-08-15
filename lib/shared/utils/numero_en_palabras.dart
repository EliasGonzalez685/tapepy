/// Convierte un número de 0 a 99 a su forma escrita en español, con
/// tildes correctas (dieciséis, veintidós, veintitrés...). Solo cubre
/// el rango que necesitan las fechas de documentos formales (día del
/// mes y las dos últimas cifras del año).
String numeroEnPalabras0a99(int n) {
  const unidades = [
    'cero', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve',
    'diez', 'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete',
    'dieciocho', 'diecinueve', 'veinte', 'veintiuno', 'veintidós', 'veintitrés',
    'veinticuatro', 'veinticinco', 'veintiséis', 'veintisiete', 'veintiocho', 'veintinueve',
  ];
  if (n < 0) return '';
  if (n <= 29) return unidades[n];
  const decenas = {30: 'treinta', 40: 'cuarenta', 50: 'cincuenta', 60: 'sesenta', 70: 'setenta', 80: 'ochenta', 90: 'noventa'};
  final decena = (n ~/ 10) * 10;
  final resto = n % 10;
  final palabraDecena = decenas[decena] ?? '';
  if (resto == 0) return palabraDecena;
  return '$palabraDecena y ${unidades[resto]}';
}

/// "dos mil veintiséis" para 2026, etc. Cubre 2000-2099, que es el
/// rango relevante para la vida útil de la app; fuera de ese rango
/// devuelve el número tal cual como respaldo.
String anioEnPalabras(int anio) {
  if (anio < 2000 || anio > 2099) return '$anio';
  final resto = anio - 2000;
  if (resto == 0) return 'dos mil';
  return 'dos mil ${numeroEnPalabras0a99(resto)}';
}

/// "a los veintidós días" o, para el día 1, "al primer día" (así se lee
/// mejor en un documento formal en español).
String diaEnPalabrasParaFecha(int dia) {
  if (dia == 1) return 'al primer día';
  return 'a los ${numeroEnPalabras0a99(dia)} días';
}
