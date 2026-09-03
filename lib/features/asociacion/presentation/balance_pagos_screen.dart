import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/organizacion_branding.dart';
import '../data/balance_pagos.dart';
import '../data/parada_detalle_service.dart';

const _meses = [
  '',
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// Balance detallado de pagos de una parada: total recaudado vs
/// pendiente/atrasado, agrupado por mes y motivo de pago, y desglosado
/// por conductor. Solo lo ven presidente de parada y presidente de
/// asociación (y por herencia, dueño de plataforma) — el conductor solo
/// ve sus propios pagos en "Mis pagos".
class BalancePagosScreen extends StatefulWidget {
  final String paradaId;
  final String paradaNombre;
  final ParadaDetalleService service;
  const BalancePagosScreen({
    super.key,
    required this.paradaId,
    required this.paradaNombre,
    required this.service,
  });

  @override
  State<BalancePagosScreen> createState() => _BalancePagosScreenState();
}

class _BalancePagosScreenState extends State<BalancePagosScreen> {
  late Future<BalancePagosParada> _future;
  bool _generandoPdf = false;
  bool _compartiendoPdf = false;
  OrganizacionBranding? _organizacion;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarOrganizacion();
  }

  void _cargar() {
    _future = widget.service.cargarCuotasParaBalance(widget.paradaId).then(calcularBalancePagos);
  }

  /// La parada ya sabe a qué organización pertenece — se pide así en
  /// vez de agregar un parámetro más al widget, para no tener que tocar
  /// los dos lugares desde donde se abre esta pantalla.
  Future<void> _cargarOrganizacion() async {
    try {
      final row = await SupabaseConfig.client
          .from('paradas')
          .select('organizaciones(id, nombre, nombre_completo, tagline, '
              'logo_asset, color_primario, carnet_subtitulo, '
              'mostrar_banderas_frontera, membrete_legal, telefono_membrete)')
          .eq('id', widget.paradaId)
          .single();
      final organizacionMap = row['organizaciones'] as Map<String, dynamic>?;
      if (organizacionMap == null || !mounted) return;
      setState(() => _organizacion = OrganizacionBranding.fromMap(organizacionMap));
    } on PostgrestException {
      // Si falla, el PDF se genera igual con el membrete genérico.
    }
  }

  Future<void> _generarPdf(BalancePagosParada balance) async {
    setState(() => _generandoPdf = true);
    try {
      final bytes = await _construirPdfBalance(
          paradaNombre: widget.paradaNombre, balance: balance, organizacion: _organizacion);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'balance_pagos.pdf');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo generar el PDF. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  Future<void> _compartirPdf(BalancePagosParada balance) async {
    setState(() => _compartiendoPdf = true);
    try {
      final bytes = await _construirPdfBalance(
          paradaNombre: widget.paradaNombre, balance: balance, organizacion: _organizacion);
      await Printing.sharePdf(bytes: bytes, filename: 'balance_pagos.pdf');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo compartir el PDF. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _compartiendoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoMonto = NumberFormat.decimalPattern('es');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance de pagos'),
        actions: [
          FutureBuilder<BalancePagosParada>(
            future: _future,
            builder: (context, snapshot) {
              final balance = snapshot.data;
              if (balance == null || balance.estaVacio) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: _generandoPdf
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: 'Exportar a PDF',
                    onPressed: _generandoPdf ? null : () => _generarPdf(balance),
                  ),
                  IconButton(
                    icon: _compartiendoPdf
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.share_outlined),
                    tooltip: 'Compartir PDF',
                    onPressed: _compartiendoPdf ? null : () => _compartirPdf(balance),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<BalancePagosParada>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('No se pudo cargar: ${snapshot.error}'));
          }
          final balance = snapshot.data!;
          if (balance.estaVacio) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    const Text('Todavía no hay pagos registrados en esta parada', textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.paradaNombre, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _ResumenTotales(balance: balance, formatoMonto: formatoMonto),
              const SizedBox(height: 24),
              Text('Por mes y motivo', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _TablaPorMesMotivo(balance: balance, formatoMonto: formatoMonto),
              const SizedBox(height: 24),
              Text('Por conductor', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _TablaPorConductor(balance: balance, formatoMonto: formatoMonto),
            ],
          );
        },
      ),
    );
  }
}

class _ResumenTotales extends StatelessWidget {
  final BalancePagosParada balance;
  final NumberFormat formatoMonto;
  const _ResumenTotales({required this.balance, required this.formatoMonto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TarjetaTotal(
            titulo: 'Recaudado',
            monto: balance.totalRecaudado,
            color: AppTheme.estadoOk,
            formatoMonto: formatoMonto,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TarjetaTotal(
            titulo: 'Pendiente',
            monto: balance.totalPendiente,
            color: AppTheme.estadoAtencion,
            formatoMonto: formatoMonto,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TarjetaTotal(
            titulo: 'Atrasado',
            monto: balance.totalAtrasado,
            color: AppTheme.estadoUrgente,
            formatoMonto: formatoMonto,
          ),
        ),
      ],
    );
  }
}

class _TarjetaTotal extends StatelessWidget {
  final String titulo;
  final double monto;
  final Color color;
  final NumberFormat formatoMonto;
  const _TarjetaTotal({
    required this.titulo,
    required this.monto,
    required this.color,
    required this.formatoMonto,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 6),
            Text('₲ ${formatoMonto.format(monto)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _TablaPorMesMotivo extends StatelessWidget {
  final BalancePagosParada balance;
  final NumberFormat formatoMonto;
  const _TablaPorMesMotivo({required this.balance, required this.formatoMonto});

  @override
  Widget build(BuildContext context) {
    int? anioActual;
    int? mesActual;
    final widgets = <Widget>[];
    for (final grupo in balance.porMesMotivo) {
      if (grupo.anio != anioActual || grupo.mes != mesActual) {
        anioActual = grupo.anio;
        mesActual = grupo.mes;
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${_meses[grupo.mes]} ${grupo.anio}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
        );
      }
      widgets.add(Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(grupo.motivo, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  if (grupo.recaudado > 0)
                    _EtiquetaMonto(
                        label: 'Recaudado', monto: grupo.recaudado, color: AppTheme.estadoOk, formatoMonto: formatoMonto),
                  if (grupo.pendiente > 0)
                    _EtiquetaMonto(
                        label: 'Pendiente',
                        monto: grupo.pendiente,
                        color: AppTheme.estadoAtencion,
                        formatoMonto: formatoMonto),
                  if (grupo.atrasado > 0)
                    _EtiquetaMonto(
                        label: 'Atrasado',
                        monto: grupo.atrasado,
                        color: AppTheme.estadoUrgente,
                        formatoMonto: formatoMonto),
                  if (grupo.exonerado > 0)
                    _EtiquetaMonto(
                        label: 'Exonerado', monto: grupo.exonerado, color: Colors.grey, formatoMonto: formatoMonto),
                ],
              ),
            ],
          ),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}

class _EtiquetaMonto extends StatelessWidget {
  final String label;
  final double monto;
  final Color color;
  final NumberFormat formatoMonto;
  const _EtiquetaMonto({
    required this.label,
    required this.monto,
    required this.color,
    required this.formatoMonto,
  });

  @override
  Widget build(BuildContext context) {
    return Text('$label: ₲ ${formatoMonto.format(monto)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12));
  }
}

class _TablaPorConductor extends StatelessWidget {
  final BalancePagosParada balance;
  final NumberFormat formatoMonto;
  const _TablaPorConductor({required this.balance, required this.formatoMonto});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: balance.porConductor.map((c) {
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            title: Text(c.nombre),
            subtitle: Text('${c.cantidadPagos} pago(s) registrado(s)'),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (c.pagado > 0)
                  Text('Pagó: ₲ ${formatoMonto.format(c.pagado)}',
                      style: const TextStyle(color: AppTheme.estadoOk, fontWeight: FontWeight.w600, fontSize: 12)),
                if (c.debe > 0)
                  Text('Debe: ₲ ${formatoMonto.format(c.debe)}',
                      style:
                          const TextStyle(color: AppTheme.estadoUrgente, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

Future<Uint8List> _construirPdfBalance({
  required String paradaNombre,
  required BalancePagosParada balance,
  required OrganizacionBranding? organizacion,
}) async {
  final doc = pw.Document();
  final org = organizacion ??
      const OrganizacionBranding(
        id: '',
        nombre: 'TapePy',
        nombreCompleto: 'TapePy',
        tagline: '',
        logoAsset: 'assets/images/tapepy_logo_blanco.png',
        colorPrimario: Color(0xFF8B0000),
      );
  final rojo = PdfColor.fromHex(
      '#${org.colorPrimario.value.toRadixString(16).substring(2)}');
  final azul = PdfColor.fromHex('#1B3A8C');
  final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
  final formatoMonto = NumberFormat.decimalPattern('es');

  final logoBytes = (await rootBundle.load(org.logoAsset)).buffer.asUint8List();
  final logoImage = pw.MemoryImage(logoBytes);

  pw.Widget membrete() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(org.nombre.toUpperCase(),
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
          pw.SizedBox(height: 14),
          pw.Text('BALANCE DE PAGOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text(paradaNombre.toUpperCase(),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: rojo)),
          pw.SizedBox(height: 2),
          pw.Text('Generado el ${formatoFecha.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 12),
        ],
      );

  pw.Widget celda(String texto, {bool header = false, bool angosta = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Text(
          texto,
          textAlign: angosta ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: header ? PdfColors.white : PdfColors.black,
          ),
        ),
      );

  final filasResumen = pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: rojo),
        children: [
          celda('Recaudado', header: true),
          celda('Pendiente', header: true),
          celda('Atrasado', header: true),
        ],
      ),
      pw.TableRow(children: [
        celda('₲ ${formatoMonto.format(balance.totalRecaudado)}'),
        celda('₲ ${formatoMonto.format(balance.totalPendiente)}'),
        celda('₲ ${formatoMonto.format(balance.totalAtrasado)}'),
      ]),
    ],
  );

  final filasMesMotivo = pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: rojo),
        children: [
          celda('Mes', header: true),
          celda('Motivo', header: true),
          celda('Recaudado', header: true),
          celda('Pendiente', header: true),
          celda('Atrasado', header: true),
        ],
      ),
      ...balance.porMesMotivo.asMap().entries.map((entry) {
        final g = entry.value;
        final par = entry.key.isEven;
        return pw.TableRow(
          decoration: pw.BoxDecoration(color: par ? PdfColors.white : PdfColors.grey100),
          children: [
            celda('${_meses[g.mes]} ${g.anio}'),
            celda(g.motivo),
            celda('₲ ${formatoMonto.format(g.recaudado)}'),
            celda('₲ ${formatoMonto.format(g.pendiente)}'),
            celda('₲ ${formatoMonto.format(g.atrasado)}'),
          ],
        );
      }),
    ],
  );

  final filasConductor = pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
    children: [
      pw.TableRow(
        decoration: pw.BoxDecoration(color: rojo),
        children: [
          celda('Conductor', header: true),
          celda('Pagó', header: true),
          celda('Debe', header: true),
        ],
      ),
      ...balance.porConductor.asMap().entries.map((entry) {
        final c = entry.value;
        final par = entry.key.isEven;
        return pw.TableRow(
          decoration: pw.BoxDecoration(color: par ? PdfColors.white : PdfColors.grey100),
          children: [
            celda(c.nombre),
            celda('₲ ${formatoMonto.format(c.pagado)}'),
            celda('₲ ${formatoMonto.format(c.debe)}'),
          ],
        );
      }),
    ],
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => context.pageNumber == 1 ? membrete() : pw.SizedBox.shrink(),
      build: (context) => [
        filasResumen,
        pw.SizedBox(height: 18),
        pw.Text('Por mes y motivo', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        filasMesMotivo,
        pw.SizedBox(height: 18),
        pw.Text('Por conductor', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        filasConductor,
      ],
    ),
  );

  return doc.save();
}
