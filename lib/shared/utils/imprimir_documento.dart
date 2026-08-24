import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

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

/// Deja compartir VARIOS documentos ya subidos de una sola vez --
/// cada uno sigue siendo su propio PDF, WhatsApp (u otra app) los
/// recibe todos juntos en el mismo envío en vez de mandarlos uno por
/// uno. Pedido de Elias 2026-08-22: la idea anterior era juntar las
/// fotos en una sola hoja nueva armada por la app, pero la librería de
/// PDF no terminó de cooperar con ese layout -- esto es más simple y
/// resuelve lo que realmente hacía falta (mandar varios documentos
/// juntos), sin tener que dibujar nada nuevo.
Future<void> compartirVariosDocumentos({
  required BuildContext context,
  required Future<String> Function(String path) obtenerUrlFirmada,
  required List<({String path, String nombreSugerido})> documentos,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final temporal = await getTemporaryDirectory();
    final archivos = <XFile>[];
    for (final doc in documentos) {
      final bytes = await _descargarComoPdf(obtenerUrlFirmada, doc.path);
      final nombre =
          doc.nombreSugerido.toLowerCase().endsWith('.pdf') ? doc.nombreSugerido : '${doc.nombreSugerido}.pdf';
      final sello = DateTime.now().microsecondsSinceEpoch;
      final archivoTemporal = File('${temporal.path}/${sello}_$nombre');
      await archivoTemporal.writeAsBytes(bytes);
      archivos.add(XFile(archivoTemporal.path, mimeType: 'application/pdf', name: nombre));
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await SharePlus.instance.share(ShareParams(files: archivos));
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudieron compartir los documentos. Intentá de nuevo.')),
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
