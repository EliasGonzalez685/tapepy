import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../shared/models/organizacion_branding.dart';
import '../data/perfil_service.dart';
import 'qr_pdf.dart';

/// Carnet digital del socio: vertical, frente y reverso (se toca la
/// tarjeta para dar vuelta). Muestra la organización real del socio
/// (Traude, FETACE, etc., vía datos.organizacion), no la marca TapePy.
/// El QR codifica la URL pública de verificación (Edge
/// Function `verificar-carnet`), así que cualquier lector de QR lo abre
/// directo y muestra nombre/foto/cédula/organización si el carnet está
/// vigente.
class CarnetScreen extends StatefulWidget {
  final String usuarioId;
  const CarnetScreen({super.key, required this.usuarioId});

  @override
  State<CarnetScreen> createState() => _CarnetScreenState();
}

class _CarnetScreenState extends State<CarnetScreen> {
  final _service = PerfilService();
  late Future<CarnetData> _future;
  bool _generandoPdf = false;
  bool _compartiendoPdf = false;
  bool _compartiendoQr = false;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarDatosCarnet(widget.usuarioId);
  }

  Future<void> _descargarPdf(CarnetData datos) async {
    setState(() => _generandoPdf = true);
    try {
      final bytes = await _generarPdf(datos);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'carnet_${datos.nombre.replaceAll(' ', '_')}.pdf',
      );
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  Future<void> _compartirPdf(CarnetData datos) async {
    setState(() => _compartiendoPdf = true);
    try {
      final bytes = await _generarPdf(datos);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'carnet_${datos.nombre.replaceAll(' ', '_')}.pdf',
      );
    } finally {
      if (mounted) setState(() => _compartiendoPdf = false);
    }
  }

  Future<void> _compartirQr(CarnetData datos) async {
    setState(() => _compartiendoQr = true);
    try {
      final bytes = await generarPdfQr(datos);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'qr_${datos.nombre.replaceAll(' ', '_')}.pdf',
      );
    } finally {
      if (mounted) setState(() => _compartiendoQr = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi carnet')),
      body: FutureBuilder<CarnetData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('No se pudo cargar el carnet: ${snapshot.error}'));
          }
          final datos = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: _CarnetFlipCard(datos: datos)),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Tocá la tarjeta para ver el reverso',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _generandoPdf ? null : () => _descargarPdf(datos),
                style: FilledButton.styleFrom(
                    backgroundColor: datos.organizacion.colorPrimario),
                icon: _generandoPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_generandoPdf ? 'Generando...' : 'Descargar / Imprimir PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _compartiendoPdf ? null : () => _compartirPdf(datos),
                icon: _compartiendoPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_outlined),
                label: Text(_compartiendoPdf ? 'Generando...' : 'Compartir PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _compartiendoQr ? null : () => _compartirQr(datos),
                icon: _compartiendoQr
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.qr_code_2_outlined),
                label: Text(_compartiendoQr ? 'Generando...' : 'Compartir QR'),
              ),
              const SizedBox(height: 12),
              Text(
                'Escaneando el código QR se puede verificar la membresía sin '
                'necesidad de tener la app instalada.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Tarjeta vertical con animación de vuelta (frente/reverso), como un
/// carnet físico real.
class _CarnetFlipCard extends StatefulWidget {
  final CarnetData datos;
  const _CarnetFlipCard({required this.datos});

  @override
  State<_CarnetFlipCard> createState() => _CarnetFlipCardState();
}

class _CarnetFlipCardState extends State<_CarnetFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _frente = true;

  void _voltear() {
    if (_frente) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    setState(() => _frente = !_frente);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tamaño reducido pedido por Elias 2026-08-25: misma proporción que
    // el carnet en PDF (50mm x 90mm, ver _cardWmm/_cardHmm más abajo).
    const ancho = 250.0;
    const alto = ancho * 1.8;

    return GestureDetector(
      onTap: _voltear,
      child: SizedBox(
        width: ancho,
        height: alto,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final angulo = _controller.value * pi;
            final mostrarFrente = angulo < pi / 2;
            final cara = mostrarFrente
                ? _CaraFrente(datos: widget.datos)
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: _CaraReverso(datos: widget.datos),
                  );
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angulo),
              child: cara,
            );
          },
        ),
      ),
    );
  }
}

class _MarcoCarnet extends StatelessWidget {
  final Widget child;
  const _MarcoCarnet({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Membrete institucional (mismo lenguaje visual que el encabezado de
/// los listados imprimibles): wordmark en el color de la organización,
/// franja bandera con el logo circular superpuesto. Versión compacta
/// para que entre en el ancho angosto del carnet.
class _EncabezadoOrganizacion extends StatelessWidget {
  final OrganizacionBranding organizacion;
  const _EncabezadoOrganizacion({required this.organizacion});

  static const _azulInstitucional = Color(0xFF1B3A8C);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Column(
        children: [
          Text(
            organizacion.nombre.toUpperCase(),
            style: TextStyle(
              color: organizacion.colorPrimario,
              fontWeight: FontWeight.bold,
              fontSize: 19,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 20,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Column(
                  children: [
                    Expanded(child: Container(color: organizacion.colorPrimario)),
                    Expanded(child: Container(color: Colors.white)),
                    Expanded(child: Container(color: _azulInstitucional)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                    child: ClipOval(
                      child: Image(
                        image: AssetImage(organizacion.logoAsset),
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaraFrente extends StatelessWidget {
  final CarnetData datos;
  const _CaraFrente({required this.datos});

  @override
  Widget build(BuildContext context) {
    final inicial = datos.nombre.trim().isNotEmpty ? datos.nombre.trim()[0].toUpperCase() : '?';
    final formatoFecha = DateFormat('dd/MM/yy');

    final color = datos.organizacion.colorPrimario;
    return _MarcoCarnet(
      child: Column(
        children: [
          _EncabezadoOrganizacion(organizacion: datos.organizacion),
          const SizedBox(height: 12),
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
              image: datos.fotoPerfilUrl != null
                  ? DecorationImage(image: NetworkImage(datos.fotoPerfilUrl!), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: datos.fotoPerfilUrl == null
                ? Text(inicial,
                    style: TextStyle(color: color, fontSize: 42, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              datos.nombre,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Text(datos.rolLabel,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CampoCarnet(etiqueta: 'CÉDULA', valor: datos.cedula ?? '—'),
                const SizedBox(height: 6),
                _CampoCarnet(etiqueta: 'TELÉFONO', valor: datos.telefono ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: color.withValues(alpha: 0.08),
            child: Text(
              'Válido ${formatoFecha.format(datos.emision)} – ${formatoFecha.format(datos.vencimiento)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaraReverso extends StatelessWidget {
  final CarnetData datos;
  const _CaraReverso({required this.datos});

  @override
  Widget build(BuildContext context) {
    return _MarcoCarnet(
      child: Column(
        children: [
          _EncabezadoOrganizacion(organizacion: datos.organizacion),
          const Spacer(),
          QrImageView(
            data: SupabaseConfig.urlVerificacionCarnet(datos.qrToken),
            size: 138,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Escaneá para verificar la membresía',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                Text(
                  datos.organizacion.tagline.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (datos.organizacion.carnetSubtitulo != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    datos.organizacion.carnetSubtitulo!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 8, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
                if (datos.organizacion.mostrarBanderasFrontera) ...[
                  const SizedBox(height: 6),
                  const _FilaBanderas(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _CampoCarnet extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _CampoCarnet({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Theme.of(context).colorScheme.outline)),
        Text(valor, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Banderitas de Argentina/Paraguay/Brasil para el reverso del carnet
/// -- pedido de Elias 2026-08-25, junto con el texto de servicios
/// (rubro histórico de la asociación). De franjas horizontales para
/// Argentina/Paraguay; Brasil simplificada a verde con un círculo
/// amarillo en el centro (en vez del rombo real) para que se vea bien
/// nítida en un ícono tan chico.
class _FranjaBandera extends StatelessWidget {
  final List<Color> colores;
  const _FranjaBandera(this.colores);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 15,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.black12, width: 0.5),
      ),
      child: Column(
        children: colores.map((c) => Expanded(child: Container(color: c))).toList(),
      ),
    );
  }
}

class _BanderaBrasil extends StatelessWidget {
  const _BanderaBrasil();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 15,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF009739),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.black12, width: 0.5),
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFEDD00)),
      ),
    );
  }
}

class _FilaBanderas extends StatelessWidget {
  const _FilaBanderas();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _FranjaBandera([Color(0xFF75AADB), Colors.white, Color(0xFF75AADB)]), // Argentina
        SizedBox(width: 5),
        _FranjaBandera([Color(0xFFD52B1E), Colors.white, Color(0xFF0038A8)]), // Paraguay
        SizedBox(width: 5),
        _BanderaBrasil(),
      ],
    );
  }
}

/// ---------------------------------------------------------------------
/// PDF — frente y reverso lado a lado en una sola página vertical
/// alargada, para verse los dos de una sin pasar de hoja.
/// ---------------------------------------------------------------------

const _cardWmm = 50.0; // 5cm de ancho -- achicado a pedido de Elias 2026-08-25
const _cardHmm = 90.0; // 9cm de largo -- ídem, más alargado que un CR80 real
const _gapMm = 6.0;
const _pageMarginMm = 5.0;

Future<Uint8List> _generarPdf(CarnetData datos) async {
  final doc = pw.Document();
  final organizacion = datos.organizacion;
  final colorOrg = PdfColor.fromHex(
      '#${organizacion.colorPrimario.value.toRadixString(16).substring(2)}');
  final azul = PdfColor.fromHex('#1B3A8C');

  final pageFormat = PdfPageFormat(
    (_pageMarginMm * 2 + _cardWmm * 2 + _gapMm) * PdfPageFormat.mm,
    (_pageMarginMm * 2 + _cardHmm) * PdfPageFormat.mm,
    marginAll: _pageMarginMm * PdfPageFormat.mm,
  );

  final logoBytes = (await rootBundle.load(organizacion.logoAsset)).buffer.asUint8List();
  final logoImage = pw.MemoryImage(logoBytes);

  pw.MemoryImage? fotoImage;
  if (datos.fotoPerfilUrl != null) {
    try {
      final respuesta = await http.get(Uri.parse(datos.fotoPerfilUrl!));
      if (respuesta.statusCode == 200) {
        fotoImage = pw.MemoryImage(respuesta.bodyBytes);
      }
    } catch (_) {
      // Si falla la descarga, el carnet se genera igual sin la foto.
    }
  }

  // Mismo membrete que las listas imprimibles (ver imprimir_listado_screen.dart),
  // en versión compacta: wordmark en el color de la organización + franja
  // bandera con el logo circular superpuesto.
  pw.Widget encabezado() => pw.Container(
        width: double.infinity,
        color: PdfColors.white,
        padding: const pw.EdgeInsets.only(top: 8, bottom: 6),
        child: pw.Column(
          children: [
            pw.Text(organizacion.nombre.toUpperCase(),
                style: pw.TextStyle(
                  color: colorOrg,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.5,
                )),
            pw.SizedBox(height: 5),
            pw.SizedBox(
              height: 8,
              width: double.infinity,
              child: pw.Stack(
                alignment: pw.Alignment.centerLeft,
                children: [
                  pw.Column(
                    children: [
                      pw.Expanded(child: pw.Container(color: colorOrg)),
                      pw.Expanded(child: pw.Container(color: PdfColors.white)),
                      pw.Expanded(child: pw.Container(color: azul)),
                    ],
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 10),
                    child: pw.Container(
                      width: 20,
                      height: 20,
                      decoration: const pw.BoxDecoration(
                          shape: pw.BoxShape.circle, color: PdfColors.white),
                      padding: const pw.EdgeInsets.all(1),
                      child: pw.ClipRRect(
                        horizontalRadius: 10,
                        verticalRadius: 10,
                        child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  pw.Widget marco(pw.Widget child) => pw.Container(
        width: _cardWmm * PdfPageFormat.mm,
        height: _cardHmm * PdfPageFormat.mm,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 8,
          verticalRadius: 8,
          child: child,
        ),
      );

  final formatoFecha = DateFormat('dd/MM/yy');

  final frente = marco(
    pw.Column(
      children: [
        encabezado(),
        pw.SizedBox(height: 6),
        pw.ClipRRect(
          horizontalRadius: 8,
          verticalRadius: 8,
          child: fotoImage != null
              ? pw.Image(fotoImage, width: 80, height: 80, fit: pw.BoxFit.cover)
              : pw.Container(
                  width: 80,
                  height: 80,
                  color: PdfColors.grey300,
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    datos.nombre.trim().isNotEmpty ? datos.nombre.trim()[0].toUpperCase() : '?',
                    style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: colorOrg),
                  ),
                ),
        ),
        pw.SizedBox(height: 6),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6),
          child: pw.Text(datos.nombre,
              textAlign: pw.TextAlign.center,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Text(datos.rolLabel,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Spacer(),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CÉDULA',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
              pw.Text(datos.cedula ?? '—', style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 6),
              pw.Text('TELÉFONO',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
              pw.Text(datos.telefono ?? '—', style: const pw.TextStyle(fontSize: 12)),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          color: PdfColor(colorOrg.red, colorOrg.green, colorOrg.blue, 0.12),
          child: pw.Text(
            'Valido ${formatoFecha.format(datos.emision)} - ${formatoFecha.format(datos.vencimiento)}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorOrg),
          ),
        ),
      ],
    ),
  );

  // Banderitas de Argentina/Paraguay/Brasil para el pie del reverso --
  // mismo criterio que la versión en pantalla (ver _FranjaBandera /
  // _BanderaBrasil en carnet_screen.dart): franjas horizontales para
  // Argentina/Paraguay, y Brasil simplificada a verde con un círculo
  // amarillo en el centro para que se vea nítida en un ícono chico.
  pw.Widget franjaBandera(List<PdfColor> colores) => pw.Container(
        width: 18,
        height: 12,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.3),
          borderRadius: pw.BorderRadius.circular(1),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 1,
          verticalRadius: 1,
          child: pw.Column(
            children: colores.map((c) => pw.Expanded(child: pw.Container(color: c))).toList(),
          ),
        ),
      );

  pw.Widget banderaBrasil() => pw.Container(
        width: 18,
        height: 12,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#009739'),
          border: pw.Border.all(color: PdfColors.grey400, width: 0.3),
          borderRadius: pw.BorderRadius.circular(1),
        ),
        child: pw.Container(
          width: 7,
          height: 7,
          decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColor.fromHex('#FEDD00')),
        ),
      );

  final reverso = marco(
    pw.Column(
      children: [
        encabezado(),
        pw.Spacer(),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: SupabaseConfig.urlVerificacionCarnet(datos.qrToken),
          width: 78,
          height: 78,
        ),
        pw.SizedBox(height: 8),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10),
          child: pw.Text(
            'Escanea para verificar la membresia',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        pw.Spacer(),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8),
          child: pw.Column(
            children: [
              pw.Text(organizacion.tagline.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              if (organizacion.carnetSubtitulo != null) ...[
                pw.SizedBox(height: 2),
                pw.Text(organizacion.carnetSubtitulo!,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
              ],
              if (organizacion.mostrarBanderasFrontera) ...[
                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    franjaBandera(
                        [PdfColor.fromHex('#75AADB'), PdfColors.white, PdfColor.fromHex('#75AADB')]),
                    pw.SizedBox(width: 4),
                    franjaBandera(
                        [PdfColor.fromHex('#D52B1E'), PdfColors.white, PdfColor.fromHex('#0038A8')]),
                    pw.SizedBox(width: 4),
                    banderaBrasil(),
                  ],
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 8),
      ],
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (context) {
        return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            frente,
            pw.SizedBox(width: _gapMm * PdfPageFormat.mm),
            reverso,
          ],
        );
      },
    ),
  );

  return doc.save();
}
