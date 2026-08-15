import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../shared/utils/firma_cargo.dart';
import '../../../shared/utils/numero_en_palabras.dart';
import '../data/constancia_service.dart';

const _meses = [
  '',
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Constancia formal: mismo membrete que el listado de socios y el
/// balance de pagos, pero el cuerpo es un párrafo de texto (no una
/// tabla) — y deja uno o dos bloques de firma al final (presidente de
/// asociación y/o de parada, según lo que haya elegido quien imprime).
/// Cada bloque lleva el cargo formateado (ver [cargoPresidenteAsociacion]
/// y [cargoPresidenteParada]) y el nombre de la persona debajo; la
/// imagen de la firma solo aparece si esa autoridad ya subió su firma
/// digital y fue incluida — si no, queda la línea en blanco para firmar
/// a mano.
Future<Uint8List> construirPdfConstancia(
  ConstanciaParaImprimir datos, {
  bool incluirAsociacion = true,
  Uint8List? firmaAsociacionBytes,
  String? nombreAsociacion,
  bool incluirParada = false,
  Uint8List? firmaParadaBytes,
  String? nombreParada,
}) async {
  final doc = pw.Document();
  final rojo = PdfColor.fromHex('#CC0000');
  final azul = PdfColor.fromHex('#1B3A8C');
  final formatoFechaGeneracion = DateFormat('dd/MM/yyyy HH:mm');

  final logoBytes = (await rootBundle.load('assets/images/traude_logo.png')).buffer.asUint8List();
  final logoImage = pw.MemoryImage(logoBytes);

  pw.Widget membrete() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('T.R.A.U.D.E.',
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: rojo, letterSpacing: 3)),
          pw.SizedBox(height: 8),
          pw.Stack(
            alignment: pw.Alignment.centerLeft,
            children: [
              pw.Container(
                height: 12,
                width: double.infinity,
                child: pw.Column(
                  children: [
                    pw.Expanded(child: pw.Container(color: rojo)),
                    pw.Expanded(child: pw.Container(color: PdfColors.white)),
                    pw.Expanded(child: pw.Container(color: azul)),
                  ],
                ),
              ),
              pw.Container(
                width: 40,
                height: 40,
                decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColors.white),
                padding: const pw.EdgeInsets.all(2),
                child: pw.ClipRRect(
                  horizontalRadius: 20,
                  verticalRadius: 20,
                  child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('CONSTANCIA', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
          pw.SizedBox(height: 4),
          pw.Text('Generado el ${formatoFechaGeneracion.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 26),
        ],
      );

  final ciTexto = datos.cedula != null && datos.cedula!.isNotEmpty
      ? 'con Cédula de Identidad Nº ${datos.cedula}, '
      : '';
  final parrafo1 =
      'Por medio de la presente se hace constar que el/la Sr./Sra. ${datos.nombre}, $ciTexto'
      'es ${datos.tipoSocio} de una línea de transporte de la Parada ${datos.paradaNombre}, '
      'perteneciente a la Asociación ${datos.organizacionNombre}.';

  final diaTexto = diaEnPalabrasParaFecha(datos.fecha.day);
  final mesTexto = _meses[datos.fecha.month];
  final anioTexto = anioEnPalabras(datos.fecha.year);
  final parrafo2 =
      'Se expide la presente constancia a pedido del interesado, para los fines que estime conveniente, '
      '$diaTexto del mes de $mesTexto del año $anioTexto.';

  pw.Widget bloqueFirma(String cargo, String? nombre, Uint8List? bytes) => pw.Column(
        children: [
          if (bytes != null)
            pw.Container(
              height: 45,
              width: 150,
              alignment: pw.Alignment.bottomCenter,
              child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
            )
          else
            pw.SizedBox(height: 45),
          pw.Container(width: 150, height: 0.8, color: PdfColors.grey700),
          pw.SizedBox(height: 4),
          pw.Text(cargo,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          if (nombre != null && nombre.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(nombre,
                textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ],
      );

  final bloquesFirma = <pw.Widget>[
    if (incluirAsociacion)
      bloqueFirma(cargoPresidenteAsociacion(datos.organizacionNombre), nombreAsociacion, firmaAsociacionBytes),
    if (incluirParada) bloqueFirma(cargoPresidenteParada(datos.paradaNombre), nombreParada, firmaParadaBytes),
  ];

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          membrete(),
          pw.Text(parrafo1, style: const pw.TextStyle(fontSize: 12), textAlign: pw.TextAlign.justify),
          pw.SizedBox(height: 14),
          pw.Text(parrafo2, style: const pw.TextStyle(fontSize: 12), textAlign: pw.TextAlign.justify),
          pw.SizedBox(height: 60),
          if (bloquesFirma.isNotEmpty)
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly, children: bloquesFirma),
        ],
      ),
    ),
  );

  return doc.save();
}
