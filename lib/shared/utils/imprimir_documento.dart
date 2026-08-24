import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Abre el diálogo nativo de impresión/guardado con el archivo REAL de
/// un documento subido (cédula, licencia, habilitación municipal,
/// etc.), sin importar quién lo haya subido — se usa tanto desde el
/// panel del presidente de asociación como del presidente de parada,
/// ambos con permiso de solo lectura sobre estos archivos.
///
/// El bucket es privado, así que primero hay que resolver una URL
/// firmada. Si el archivo ya es un PDF se manda tal cual; si es una
/// imagen (la mayoría de los documentos son fotos) se envuelve en una
/// página PDF de una sola hoja para poder imprimirla igual. La
/// detección de PDF es por los primeros bytes del archivo (firma
/// "%PDF"), no por la extensión del nombre — más confiable.
Future<void> imprimirArchivoDocumento({
  required BuildContext context,
  required Future<String> Function(String path) obtenerUrlFirmada,
  required String path,
  required String nombreSugerido,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final pdfBytes = await _descargarComoPdf(obtenerUrlFirmada, path);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: nombreSugerido);
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el documento. Intentá de nuevo.')),
    );
  }
}

/// Abre el selector nativo para compartir el documento (WhatsApp,
/// correo, etc.) en vez del diálogo de imprimir/guardar -- pedido de
/// Elias 2026-08-22: hoy la única forma de sacar un documento de la app
/// era descargarlo, y quiere poder mandarlo directo. Usa la misma
/// resolución PDF que [imprimirArchivoDocumento] (URL firmada + armado
/// de PDF si es una foto), solo cambia qué hace con el resultado.
Future<void> compartirArchivoDocumento({
  required BuildContext context,
  required Future<String> Function(String path) obtenerUrlFirmada,
  required String path,
  required String nombreSugerido,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final pdfBytes = await _descargarComoPdf(obtenerUrlFirmada, path);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await Printing.sharePdf(bytes: pdfBytes, filename: nombreSugerido);
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo compartir el documento. Intentá de nuevo.')),
    );
  }
}

/// Abre el diálogo nativo de imprimir/guardar para un PDF que ya está
/// armado en memoria (no hay que resolver ninguna URL) -- se usa para
/// el resultado de [combinarDocumentosEnUnaHoja].
Future<void> imprimirBytesPdf({
  required BuildContext context,
  required Uint8List bytes,
  required String nombreSugerido,
}) async {
  try {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: nombreSugerido);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el documento. Intentá de nuevo.')),
    );
  }
}

/// Igual que [compartirArchivoDocumento] pero para un PDF que ya está
/// armado en memoria.
Future<void> compartirBytesPdf({
  required BuildContext context,
  required Uint8List bytes,
  required String nombreSugerido,
}) async {
  try {
    await Printing.sharePdf(bytes: bytes, filename: nombreSugerido);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo compartir el documento. Intentá de nuevo.')),
    );
  }
}

/// Junta hasta 4 documentos ya subidos (cada uno ya es su propio PDF)
/// en UNA sola hoja nueva, apilados uno debajo del otro a todo el
/// ancho -- pedido de Elias 2026-08-22: hay documentos que conviene
/// tener juntos al imprimir (cédula + cédula verde + habilitación, por
/// ejemplo). No reemplaza nada: cada documento sigue existiendo tal
/// cual estaba, esto arma una copia extra combinada para ver/imprimir/
/// compartir.
///
/// Cada imagen ocupa una franja de alto fijo (el alto disponible de la
/// hoja dividido entre la cantidad de documentos elegidos) a todo el
/// ancho -- pedido de Elias 2026-08-22 (2ª vuelta): la primera versión
/// las armaba en una grilla que terminaba MUY chica y amontonada en el
/// medio de la hoja (el `Expanded` de la librería de PDF no repartía
/// el alto como en Flutter). Con un alto explícito por franja, cada
/// documento queda grande y legible, como el ejemplo que pasó.
///
/// (3ª vuelta) Con solo la altura fija en el `Container` las fotos
/// SEGUÍAN saliendo chiquitas arriba de cada franja: en esta librería
/// `BoxFit.contain` necesita que la imagen misma reciba un ancho Y un
/// alto explícitos para escalar hasta ese tamaño -- si solo el
/// contenedor los tiene, la imagen se dibuja a un tamaño propio chico
/// en vez de crecer para llenar la franja. Ahora el ancho y el alto se
/// le pasan directo a `pw.Image`.
///
/// Rasteriza la primera página de cada PDF de origen a imagen (con
/// [Printing.raster]) para poder acomodarla -- si algún documento
/// tiene más de una página (frente/verso combinados al subir), solo
/// entra la primera.
Future<Uint8List> combinarDocumentosEnUnaHoja(List<Uint8List> pdfsBytes) async {
  final imagenes = <pw.MemoryImage>[];
  for (final bytes in pdfsBytes) {
    await for (final pagina in Printing.raster(bytes, pages: [0], dpi: 200)) {
      final png = await pagina.toPng();
      imagenes.add(pw.MemoryImage(png));
      break;
    }
  }
  if (imagenes.isEmpty) {
    final doc = pw.Document();
    doc.addPage(pw.Page(build: (context) => pw.Container()));
    return doc.save();
  }

  const pageFormat = PdfPageFormat.a4;
  const margen = 24.0;
  const espacio = 14.0;
  final anchoDisponible = pageFormat.width - margen * 2;
  final altoDisponible = pageFormat.height - margen * 2;
  final altoPorImagen = (altoDisponible - espacio * (imagenes.length - 1)) / imagenes.length;

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(margen),
      build: (context) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < imagenes.length; i++) ...[
            if (i > 0) pw.SizedBox(height: espacio),
            pw.Image(
              imagenes[i],
              width: anchoDisponible,
              height: altoPorImagen,
              fit: pw.BoxFit.contain,
            ),
          ],
        ],
      ),
    ),
  );
  return doc.save();
}

Future<Uint8List> _descargarComoPdf(
  Future<String> Function(String path) obtenerUrlFirmada,
  String path,
) async {
  final url = await obtenerUrlFirmada(path);
  final respuesta = await http.get(Uri.parse(url));
  if (respuesta.statusCode != 200) {
    throw Exception('No se pudo descargar el archivo (${respuesta.statusCode})');
  }
  final bytes = respuesta.bodyBytes;
  return _esPdf(bytes) ? bytes : await _envolverImagenEnPdf(bytes);
}

bool _esPdf(Uint8List bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x25 && // %
      bytes[1] == 0x50 && // P
      bytes[2] == 0x44 && // D
      bytes[3] == 0x46; // F
}

Future<Uint8List> _envolverImagenEnPdf(Uint8List bytes) async {
  final doc = pw.Document();
  final imagen = pw.MemoryImage(bytes);
  doc.addPage(
    pw.Page(
      build: (context) => pw.Center(child: pw.Image(imagen, fit: pw.BoxFit.contain)),
    ),
  );
  return doc.save();
}
