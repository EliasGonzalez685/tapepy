import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/models/user_role.dart';
import '../../firma/data/firma_service.dart';
import '../../firma/presentation/mi_firma_screen.dart';
import '../data/parada_detalle_service.dart';

/// Qué dato puede sumar el presidente al listado imprimible. `firma` no
/// es un dato del conductor — es una columna que sale en blanco a
/// propósito, para que cada uno firme a mano al lado de su fila
/// después de imprimir (no tiene nada que ver con la firma digital del
/// presidente, que es otra cosa).
enum _Columna {
  nombre,
  cedula,
  telefono,
  turno,
  chapa,
  marca,
  modelo,
  anio,
  color,
  resolucion,
  firma,
}

extension on _Columna {
  String get etiqueta {
    switch (this) {
      case _Columna.nombre:
        return 'Nombre';
      case _Columna.cedula:
        return 'Cédula';
      case _Columna.telefono:
        return 'Teléfono';
      case _Columna.turno:
        return 'Turno';
      case _Columna.chapa:
        return 'Chapa Nº';
      case _Columna.marca:
        return 'Marca';
      case _Columna.modelo:
        return 'Modelo';
      case _Columna.anio:
        return 'Año';
      case _Columna.color:
        return 'Color';
      case _Columna.resolucion:
        return 'Resolución Nº';
      case _Columna.firma:
        return 'Firma';
    }
  }

  String valor(ConductorListadoItem item) {
    switch (this) {
      case _Columna.nombre:
        return item.nombre;
      case _Columna.cedula:
        return item.cedula ?? '—';
      case _Columna.telefono:
        return item.telefono ?? '—';
      case _Columna.turno:
        return _turnoLabel(item.turno);
      case _Columna.chapa:
        return item.chapa ?? '—';
      case _Columna.marca:
        return item.marca ?? '—';
      case _Columna.modelo:
        return item.modelo ?? '—';
      case _Columna.anio:
        return item.anio?.toString() ?? '—';
      case _Columna.color:
        return item.color ?? '—';
      case _Columna.resolucion:
        return item.resolucionNumero ?? '—';
      case _Columna.firma:
        return ''; // A propósito en blanco: acá firma el conductor a mano.
    }
  }

  static String _turnoLabel(String? turno) {
    if (turno == null) return '—';
    const labels = {'manana': 'Mañana', 'tarde': 'Tarde', 'noche': 'Noche', 'completo': 'Completo'};
    return labels[turno] ?? turno;
  }
}

/// Selector de columnas + generación del PDF. Sirve para los dos casos
/// pedidos por Elias: el presidente de una parada imprime solo la suya
/// (pasa [paradaId] + [paradaNombre]) y el presidente de asociación
/// imprime todas juntas (no pasa ninguno de los dos). [usuario] hace
/// falta para saber de quién es "la propia" firma y a quién pedirle "la
/// otra".
class ImprimirListadoScreen extends StatefulWidget {
  final String? paradaId;
  final String? paradaNombre;
  final Usuario usuario;
  const ImprimirListadoScreen({
    super.key,
    required this.usuario,
    this.paradaId,
    this.paradaNombre,
  });

  bool get _todasLasParadas => paradaId == null;

  @override
  State<ImprimirListadoScreen> createState() => _ImprimirListadoScreenState();
}

class _ImprimirListadoScreenState extends State<ImprimirListadoScreen> {
  final _service = ParadaDetalleService();
  final _firmaService = FirmaService();
  late Future<List<ConductorListadoItem>> _future;
  late final Set<_Columna> _seleccionadas;
  bool _generando = false;

  // Se completan solos apenas cargan los datos (ver _inicializarSeleccion).
  List<ConductorListadoItem>? _items;
  Set<ConductorListadoItem>? _seleccionados;
  String? _paradaFiltro; // null = todas las paradas juntas

  // --- Firmas ---
  bool _cargandoFirmas = false;
  bool _solicitandoFirma = false;
  String? _miFirmaPath;
  bool _incluirMiFirma = false;
  String? _paradaIdConsultada; // para no volver a pedir si no cambió el alcance
  String? _otroPresidenteId;
  String? _otroFirmaPath;
  EstadoFirma _estadoOtraFirma = EstadoFirma.ninguna;
  bool _incluirOtraFirma = false;

  String get _otroRolLabel =>
      widget.usuario.rol == UserRole.presidenteAsociacion ? 'Presidente de Parada' : 'Presidente de Asociación';

  List<_Columna> get _columnasDisponibles => _Columna.values;

  /// Nombres de parada presentes en los datos cargados, para el
  /// selector — solo tiene sentido cuando se imprime de toda la
  /// organización (el presidente de una parada ya está en la suya).
  List<String> get _paradasDisponibles {
    final nombres = (_items ?? []).map((i) => i.paradaNombre).whereType<String>().toSet().toList();
    nombres.sort();
    return nombres;
  }

  List<ConductorListadoItem> get _itemsFiltrados {
    final items = _items ?? [];
    if (_paradaFiltro == null) return items;
    return items.where((i) => i.paradaNombre == _paradaFiltro).toList();
  }

  /// Parada puntual en juego para efectos de firma: la propia (si el
  /// presidente de parada está imprimiendo lo suyo) o la elegida en el
  /// filtro (si el presidente de asociación acotó a una sola). Si son
  /// "todas las paradas" no hay una única contraparte a quien pedirle
  /// la firma.
  String? get _paradaIdActual {
    if (!widget._todasLasParadas) return widget.paradaId;
    if (_paradaFiltro == null) return null;
    for (final item in _items ?? <ConductorListadoItem>[]) {
      if (item.paradaNombre == _paradaFiltro) return item.paradaId;
    }
    return null;
  }

  void _inicializarSeleccion(List<ConductorListadoItem> items) {
    _items ??= items;
    _seleccionados ??= items.toSet();
  }

  void _cambiarParadaFiltro(String? parada) {
    setState(() {
      _paradaFiltro = parada;
      // Al cambiar de parada, arrancamos con todos tildados de nuevo —
      // es lo más predecible.
      _seleccionados = _itemsFiltrados.toSet();
    });
    _actualizarFirmasSiHizoFalta();
  }

  void _actualizarFirmasSiHizoFalta() {
    final paradaId = _paradaIdActual;
    if (paradaId == _paradaIdConsultada) return;
    _cargarFirmas();
  }

  Future<void> _cargarFirmas() async {
    final usuario = widget.usuario;
    final paradaId = _paradaIdActual;
    _paradaIdConsultada = paradaId;
    setState(() => _cargandoFirmas = true);
    try {
      final firmaPropia = await _firmaService.cargarFirmaUrl(usuario.id);

      String? otroId;
      String? otroFirma;
      var estado = EstadoFirma.ninguna;

      if (paradaId != null) {
        if (usuario.rol == UserRole.presidenteAsociacion) {
          otroId = await _firmaService.obtenerPresidenteParadaId(paradaId);
        } else if (usuario.organizacionId != null) {
          otroId = await _firmaService.obtenerPresidenteAsociacionId(usuario.organizacionId!);
        }
        if (otroId != null) {
          estado = await _firmaService.consultarEstado(
            solicitanteId: usuario.id,
            firmanteId: otroId,
            paradaId: paradaId,
          );
          if (estado == EstadoFirma.aprobada) {
            otroFirma = await _firmaService.cargarFirmaUrl(otroId);
          }
        }
      }

      if (!mounted || paradaId != _paradaIdConsultada) return;
      setState(() {
        _miFirmaPath = firmaPropia;
        _incluirMiFirma = firmaPropia != null;
        _otroPresidenteId = otroId;
        _estadoOtraFirma = estado;
        _otroFirmaPath = otroFirma;
        _incluirOtraFirma = estado == EstadoFirma.aprobada && otroFirma != null;
      });
    } finally {
      if (mounted) setState(() => _cargandoFirmas = false);
    }
  }

  Future<void> _solicitarOtraFirma() async {
    final usuario = widget.usuario;
    final paradaId = _paradaIdActual;
    final firmanteId = _otroPresidenteId;
    if (paradaId == null || firmanteId == null || usuario.organizacionId == null) return;
    setState(() => _solicitandoFirma = true);
    try {
      await _firmaService.solicitarFirma(
        organizacionId: usuario.organizacionId!,
        paradaId: paradaId,
        solicitanteId: usuario.id,
        firmanteId: firmanteId,
      );
      if (!mounted) return;
      setState(() => _estadoOtraFirma = EstadoFirma.pendiente);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se envió la solicitud de firma al $_otroRolLabel')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo enviar la solicitud. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _solicitandoFirma = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _seleccionadas = {_Columna.nombre, _Columna.cedula};
    _future = widget._todasLasParadas
        ? _service.cargarListadoConductoresOrganizacion(organizacionId: widget.usuario.organizacionId)
        : _service.cargarListadoConductores(widget.paradaId!);
    _cargarFirmas();
  }

  Future<void> _generarPdf() async {
    if (_seleccionadas.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Elegí al menos una columna')));
      return;
    }
    final items = _itemsFiltrados.where((i) => _seleccionados?.contains(i) ?? false).toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Elegí al menos un conductor')));
      return;
    }
    setState(() => _generando = true);
    try {
      final columnas = _columnasDisponibles.where(_seleccionadas.contains).toList();
      final subtitulo = widget._todasLasParadas ? (_paradaFiltro ?? 'TODAS LAS PARADAS') : widget.paradaNombre;

      Uint8List? firmaPropiaBytes;
      if (_incluirMiFirma && _miFirmaPath != null) {
        firmaPropiaBytes = await _descargarFirma(_miFirmaPath!);
      }
      Uint8List? firmaOtraBytes;
      if (_incluirOtraFirma && _otroFirmaPath != null) {
        firmaOtraBytes = await _descargarFirma(_otroFirmaPath!);
      }

      final bytes = await _construirPdf(
        subtitulo: subtitulo,
        columnas: columnas,
        items: items,
        firmaPropiaBytes: firmaPropiaBytes,
        firmaPropiaLabel: firmaPropiaBytes != null ? widget.usuario.rol.label : null,
        firmaOtraBytes: firmaOtraBytes,
        firmaOtraLabel: firmaOtraBytes != null ? _otroRolLabel : null,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'listado_socios.pdf');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<Uint8List?> _descargarFirma(String path) async {
    try {
      final url = await _firmaService.obtenerUrlFirmada(path);
      final respuesta = await http.get(Uri.parse(url));
      if (respuesta.statusCode == 200) return respuesta.bodyBytes;
    } catch (_) {
      // Si falla la descarga, el PDF se genera igual sin esa firma.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IMPRIMIR LISTADO')),
      body: FutureBuilder<List<ConductorListadoItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('No se pudo cargar: ${snapshot.error}'));
          }
          final items = snapshot.data ?? [];
          _inicializarSeleccion(items);
          final itemsFiltrados = _itemsFiltrados;
          final seleccionados = _seleccionados ?? {};
          final cantidadSeleccionada = itemsFiltrados.where(seleccionados.contains).length;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget._todasLasParadas
                    ? 'Elegí qué datos incluir, de qué parada y qué conductores.'
                    : 'Elegí qué datos incluir del listado de "${widget.paradaNombre}".',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              if (widget._todasLasParadas && items.isNotEmpty) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  value: _paradaFiltro,
                  decoration: const InputDecoration(labelText: 'Parada', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todas las paradas')),
                    ..._paradasDisponibles
                        .map((p) => DropdownMenuItem<String?>(value: p, child: Text(p))),
                  ],
                  onChanged: _cambiarParadaFiltro,
                ),
              ],
              const SizedBox(height: 20),
              Text('Datos a incluir', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _columnasDisponibles.map((columna) {
                  final activa = _seleccionadas.contains(columna);
                  return FilterChip(
                    label: Text(columna.etiqueta),
                    selected: activa,
                    selectedColor: AppTheme.rojoInstitucional.withValues(alpha: 0.15),
                    checkmarkColor: AppTheme.rojoInstitucional,
                    onSelected: (valor) {
                      setState(() {
                        if (valor) {
                          _seleccionadas.add(columna);
                        } else {
                          _seleccionadas.remove(columna);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Text('Firmas a incluir', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _SeccionFirmas(
                cargando: _cargandoFirmas,
                solicitando: _solicitandoFirma,
                miFirmaDisponible: _miFirmaPath != null,
                miRolLabel: widget.usuario.rol.label,
                incluirMiFirma: _incluirMiFirma,
                onCambiarMiFirma: _miFirmaPath == null
                    ? null
                    : (valor) => setState(() => _incluirMiFirma = valor),
                onIrASubirFirma: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MiFirmaScreen(usuario: widget.usuario)),
                  );
                  // Forzamos un refetch aunque el alcance (parada) no
                  // haya cambiado, porque lo que cambió es la firma
                  // propia.
                  setState(() => _paradaIdConsultada = null);
                  _cargarFirmas();
                },
                haySolaParada: _paradaIdActual != null,
                otroRolLabel: _otroRolLabel,
                otroPresidenteAsignado: _otroPresidenteId != null,
                estadoOtraFirma: _estadoOtraFirma,
                otroFirmaDisponible: _otroFirmaPath != null,
                incluirOtraFirma: _incluirOtraFirma,
                onCambiarOtraFirma: (_estadoOtraFirma == EstadoFirma.aprobada && _otroFirmaPath != null)
                    ? (valor) => setState(() => _incluirOtraFirma = valor)
                    : null,
                onSolicitarOtraFirma: _solicitarOtraFirma,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Conductores a imprimir ($cantidadSeleccionada de ${itemsFiltrados.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: itemsFiltrados.isEmpty
                        ? null
                        : () => setState(() => _seleccionados = itemsFiltrados.toSet()),
                    child: const Text('Todos'),
                  ),
                  TextButton(
                    onPressed: itemsFiltrados.isEmpty ? null : () => setState(() => _seleccionados = {}),
                    child: const Text('Ninguno'),
                  ),
                ],
              ),
              if (itemsFiltrados.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No hay conductores para esta selección.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              else
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: itemsFiltrados.map((item) {
                      return CheckboxListTile(
                        dense: true,
                        value: seleccionados.contains(item),
                        activeColor: AppTheme.rojoInstitucional,
                        title: Text(item.nombre),
                        subtitle: Text(
                          [
                            if (item.cedula != null) 'CI ${item.cedula}',
                            if (widget._todasLasParadas && item.paradaNombre != null) item.paradaNombre!,
                          ].join(' · '),
                        ),
                        onChanged: (marcado) {
                          setState(() {
                            _seleccionados ??= {};
                            if (marcado == true) {
                              _seleccionados!.add(item);
                            } else {
                              _seleccionados!.remove(item);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: (_generando || cantidadSeleccionada == 0) ? null : _generarPdf,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
                icon: _generando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_generando ? 'Generando...' : 'Generar PDF'),
              ),
              if (items.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Todavía no hay conductores para listar.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Bloque de selección de firmas: la propia (directa, si ya la subió) y
/// la del otro presidente (directa si ya está aprobada, con botón de
/// solicitud si todavía no).
class _SeccionFirmas extends StatelessWidget {
  final bool cargando;
  final bool solicitando;
  final bool miFirmaDisponible;
  final String miRolLabel;
  final bool incluirMiFirma;
  final ValueChanged<bool>? onCambiarMiFirma;
  final VoidCallback onIrASubirFirma;
  final bool haySolaParada;
  final String otroRolLabel;
  final bool otroPresidenteAsignado;
  final EstadoFirma estadoOtraFirma;
  final bool otroFirmaDisponible;
  final bool incluirOtraFirma;
  final ValueChanged<bool>? onCambiarOtraFirma;
  final VoidCallback onSolicitarOtraFirma;

  const _SeccionFirmas({
    required this.cargando,
    required this.solicitando,
    required this.miFirmaDisponible,
    required this.miRolLabel,
    required this.incluirMiFirma,
    required this.onCambiarMiFirma,
    required this.onIrASubirFirma,
    required this.haySolaParada,
    required this.otroRolLabel,
    required this.otroPresidenteAsignado,
    required this.estadoOtraFirma,
    required this.otroFirmaDisponible,
    required this.incluirOtraFirma,
    required this.onCambiarOtraFirma,
    required this.onSolicitarOtraFirma,
  });

  @override
  Widget build(BuildContext context) {
    final subtextStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (miFirmaDisponible)
              CheckboxListTile(
                value: incluirMiFirma,
                activeColor: AppTheme.rojoInstitucional,
                title: Text('Mi firma ($miRolLabel)'),
                onChanged: onCambiarMiFirma == null ? null : (v) => onCambiarMiFirma!(v ?? false),
              )
            else
              ListTile(
                leading: Icon(Icons.draw_outlined, color: Colors.grey.shade400),
                title: const Text('No subiste tu firma todavía'),
                trailing: TextButton(onPressed: onIrASubirFirma, child: const Text('Subir')),
              ),
            const Divider(height: 1),
            if (cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else if (!haySolaParada)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Para incluir la firma del $otroRolLabel elegí una sola parada arriba.',
                  style: subtextStyle,
                ),
              )
            else if (!otroPresidenteAsignado)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('Todavía no hay $otroRolLabel asignado.', style: subtextStyle),
              )
            else
              switch (estadoOtraFirma) {
                EstadoFirma.aprobada when otroFirmaDisponible => CheckboxListTile(
                    value: incluirOtraFirma,
                    activeColor: AppTheme.rojoInstitucional,
                    title: Text('Firma del $otroRolLabel'),
                    subtitle: const Text('Autorizada'),
                    onChanged: onCambiarOtraFirma == null ? null : (v) => onCambiarOtraFirma!(v ?? false),
                  ),
                EstadoFirma.aprobada => Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('El $otroRolLabel todavía no subió su firma.', style: subtextStyle),
                  ),
                EstadoFirma.pendiente => ListTile(
                    leading: const Icon(Icons.hourglass_top_outlined, color: Colors.orange),
                    title: Text('Firma del $otroRolLabel'),
                    subtitle: const Text('Solicitud pendiente de aprobación'),
                  ),
                EstadoFirma.rechazada => ListTile(
                    leading: Icon(Icons.block_outlined, color: Theme.of(context).colorScheme.error),
                    title: Text('Firma del $otroRolLabel'),
                    subtitle: const Text('Solicitud rechazada'),
                    trailing: solicitando
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(onPressed: onSolicitarOtraFirma, child: const Text('Reintentar')),
                  ),
                EstadoFirma.ninguna => ListTile(
                    leading: const Icon(Icons.draw_outlined),
                    title: Text('Firma del $otroRolLabel'),
                    trailing: solicitando
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(onPressed: onSolicitarOtraFirma, child: const Text('Solicitar')),
                  ),
              },
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// PDF — mismo membrete que ya usa TRAUDE en sus listados en papel
/// (título rojo, texto institucional, franja bandera + logo, "LISTA DE
/// SOCIOS"), más una tabla con numeración de fila y solo las columnas
/// que el presidente eligió — la parada queda identificada como
/// subtítulo del listado, no repetida en cada fila. Si se eligió la
/// columna "Firma", esa celda queda en blanco a propósito para que cada
/// conductor firme a mano después de imprimir. Al final, si se pidió,
/// un bloque con la(s) firma(s) digital(es) de los presidentes.
/// ---------------------------------------------------------------------

Future<Uint8List> _construirPdf({
  required String? subtitulo,
  required List<_Columna> columnas,
  required List<ConductorListadoItem> items,
  Uint8List? firmaPropiaBytes,
  String? firmaPropiaLabel,
  Uint8List? firmaOtraBytes,
  String? firmaOtraLabel,
}) async {
  final doc = pw.Document();
  final rojo = PdfColor.fromHex('#CC0000');
  final azul = PdfColor.fromHex('#1B3A8C');
  final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

  final logoBytes = (await rootBundle.load('assets/images/traude_logo.png')).buffer.asUint8List();
  final logoImage = pw.MemoryImage(logoBytes);

  pw.Widget celda(String texto, {bool header = false, bool angosta = false, bool alta = false}) => pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: alta ? 16 : 6),
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

  final filas = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: rojo),
      children: [
        celda('N.º', header: true, angosta: true),
        ...columnas.map((c) => celda(c.etiqueta, header: true)),
      ],
    ),
    ...items.asMap().entries.map((entry) {
      final par = entry.key.isEven;
      return pw.TableRow(
        decoration: pw.BoxDecoration(color: par ? PdfColors.white : PdfColors.grey100),
        children: [
          celda('${entry.key + 1}', angosta: true),
          ...columnas.map((c) => celda(c.valor(entry.value), alta: c == _Columna.firma)),
        ],
      );
    }),
  ];

  pw.Widget membrete() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('T.R.A.U.D.E.',
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: rojo, letterSpacing: 3)),
          pw.SizedBox(height: 4),
          pw.Text(
            'RECONOCIDO POR EL PODER EJECUTIVO CON PERSONERÍA JURÍDICA DECRETO LEY Nº 12.189',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text('SERVICIO INTERNACIONAL DE VIAJES', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('PASAJES. EXCURSIONES. HOTELES. RECEPTIVOS Y TRASLADO',
              style: const pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 2),
          pw.Text('Cel.: (0993) 501 230', style: const pw.TextStyle(fontSize: 9)),
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
          pw.Text('LISTA DE SOCIOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          if (subtitulo != null) ...[
            pw.SizedBox(height: 3),
            pw.Text(subtitulo.toUpperCase(),
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: rojo)),
          ],
          pw.SizedBox(height: 2),
          pw.Text('Generado el ${formatoFecha.format(DateTime.now())} · ${items.length} socios',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 12),
        ],
      );

  pw.Widget bloqueFirma(Uint8List bytes, String etiqueta) => pw.Column(
        children: [
          pw.Container(
            height: 55,
            width: 160,
            alignment: pw.Alignment.bottomCenter,
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
          ),
          pw.Container(width: 160, height: 0.8, color: PdfColors.grey700),
          pw.SizedBox(height: 4),
          pw.Text(etiqueta, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      );

  final tieneFirmas = firmaPropiaBytes != null || firmaOtraBytes != null;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => context.pageNumber == 1 ? membrete() : pw.SizedBox.shrink(),
      build: (context) => [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.5),
            for (var i = 0; i < columnas.length; i++)
              i + 1: switch (columnas[i]) {
                _Columna.nombre => const pw.FlexColumnWidth(2.2),
                _Columna.firma => const pw.FlexColumnWidth(1.8),
                _ => const pw.FlexColumnWidth(1),
              },
          },
          children: filas,
        ),
        if (tieneFirmas) ...[
          pw.SizedBox(height: 50),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              if (firmaPropiaBytes != null) bloqueFirma(firmaPropiaBytes, firmaPropiaLabel ?? ''),
              if (firmaOtraBytes != null) bloqueFirma(firmaOtraBytes, firmaOtraLabel ?? ''),
            ],
          ),
        ],
      ],
    ),
  );

  return doc.save();
}
