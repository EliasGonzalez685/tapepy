import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
