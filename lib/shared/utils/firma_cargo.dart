/// Formato del cargo que va arriba del nombre en cualquier bloque de
/// firma impreso (listados, constancias): "PRESIDENTE {ORGANIZACIÓN}"
/// para el presidente de asociación, "Presidente de la Parada {nombre}"
/// para el de parada. Las paradas no tienen un número propio en el
/// sistema, solo un nombre (que puede ser textual, ej. "Parada
/// Guaraní", o directamente un número escrito como texto, ej. "Parada
/// Nº 3"), así que usamos ese nombre tal cual.
String cargoPresidenteAsociacion(String? organizacionNombre) =>
    'PRESIDENTE ${(organizacionNombre ?? 'TRAUDE').toUpperCase()}';

String cargoPresidenteParada(String? paradaNombre) => 'Presidente de la Parada ${paradaNombre ?? ''}'.trim();
