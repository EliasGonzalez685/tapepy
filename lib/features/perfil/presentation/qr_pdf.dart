import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/config/supabase_config.dart';
import '../data/perfil_service.dart';

/// PDF de una sola hoja chica con el QR de verificación, para poder
/// mandarlo por WhatsApp u otra app sin tener que abrir el carnet
/// entero. Se usa tanto desde "Mi código QR" (mi_qr_screen.dart) como
/// desde "Mi carnet" (carnet_screen.dart) -- pedido de Elias
/// 2026-08-25: el carnet necesita poder compartir el QR "como tal",
/// aparte de poder compartir el PDF completo del carnet.
Future<Uint8List> generarPdfQr(CarnetData datos) async {
  final doc = pw.Document();
  final colorOrg = PdfColor.fromHex(
      '#${datos.organizacion.colorPrimario.value.toRadixString(16).substring(2)}');

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, 110 * PdfPageFormat.mm,
          marginAll: 6 * PdfPageFormat.mm),
      build: (context) {
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(datos.organizacion.nombre.toUpperCase(),
                style: pw.TextStyle(
                    color: colorOrg,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 1.5)),
            pw.SizedBox(height: 16),
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: SupabaseConfig.urlVerificacionCarnet(datos.qrToken),
              width: 160,
              height: 160,
            ),
            pw.SizedBox(height: 14),
            pw.Text(datos.nombre,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text(datos.rolLabel, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 10),
            pw.Text('Escaneá para verificar la membresía',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        );
      },
    ),
  );

  return doc.save();
}
