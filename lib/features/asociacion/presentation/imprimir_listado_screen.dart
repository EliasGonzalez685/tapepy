import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/data/organizacion_service.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/utils/firma_cargo.dart';
import '../../firma/data/firma_service.dart';
import '../data/parada_detalle_service.dart';

/// Qué dato puede sumar el presidente al listado imprimible. `firma` no
/// es un dato del conductor — es una columna que sale en blanco a
/// propósito, para que cada uno firme a mano al lado de su fila
/// después de imprimir (no tiene nada que ver con la firma digital del
/// presidente, que es otra cosa).
enum _Columna {
  nombre,
  parada,
  cedula,
  telefono,
  turno,
  chapa,
  marca,
  modelo,
  anio,
  color,
  resolucionIndividual,
  resolucionParada,
  firma,
}

extension on _Columna {
  String get etiqueta {
    switch (this) {
      case _Columna.nombre:
        return 'Nombre';
      case _Columna.parada:
        return 'Parada';
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
      case _Columna.resolucionIndividual:
        return 'Resolución Nº (socio)';
      case _Columna.resolucionParada:
        return 'Resolución Nº (parada)';
      case _Columna.firma:
        return 'Firma';
    }
  }

  String valor(ConductorListadoItem item) {
    switch (this) {
      case _Columna.nombre:
        return item.nombre;
      case _Columna.parada:
        return item.paradaNombre ?? '—';
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
      case _Columna.resolucionIndividual:
        return item.resolucionIndividual ?? '—';
      case _Columna.resolucionParada:
        return item.resolucionParada ?? '—';
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
/// falta para saber de quién es "la propia" firma (cargo + nombre, sin
/// imagen) y quién es "el otro" presidente para imprimir su cargo +
/// nombre también.
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
  final _organizacionService = OrganizacionService();
  late Future<List<ConductorListadoItem>> _future;
  late final Set<_Columna> _seleccionadas;
  bool _generando = false;

  // Se completan solos apenas cargan los datos (ver _inicializarSeleccion).
  List<ConductorListadoItem>? _items;
  Set<ConductorListadoItem>? _seleccionados;
  String? _paradaFiltro; // null = todas las paradas juntas

  // --- Firma a mano: no hace falta una imagen digital subida, solo
  // dejar el cargo + nombre impresos con un espacio en blanco arriba
  // para que la persona firme físicamente después de imprimir (pedido
  // de Elias, 2026-08-17). Solo hace falta saber QUIÉN es el otro
  // presidente (id + nombre), no si tiene una firma digital cargada.
  bool _cargandoOtroPresidente = false;
  String? _organizacionNombre;
  bool _incluirFirmaPropia = true;
  String? _paradaIdConsultada; // para no volver a pedir si no cambió el alcance
  String? _otroPresidenteId;
  String? _otroPresidenteNombre;
  bool _incluirFirmaOtro = true;

  String get _otroRolLabel =>
      widget.usuario.rol == UserRole.presidenteAsociacion ? 'Presidente de Parada' : 'Presidente de Asociación';

  /// "Todas las paradas" sin acotar a una sola: todos los conductores
  /// elegidos, sin importar de qué parada sean, van en UNA sola tabla
  /// (no una tabla por parada) -- pedido explícito de Elias, 2026-08-17.
  /// Como puede mezclar gente de varias paradas, conviene sumar la
  /// columna "Parada" para identificar cada fila (ver _Columna.parada).
  bool get _modoBulk => widget._todasLasParadas && _paradaFiltro == null;

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

  /// Igual que [_paradaIdActual] pero el nombre, para armar el cargo del
  /// presidente de parada en el bloque de firma.
  String? get _paradaNombreActual => widget._todasLasParadas ? _paradaFiltro : widget.paradaNombre;

  /// Cargo que va arriba del nombre en el bloque de firma propio.
  String get _cargoPropio => widget.usuario.rol == UserRole.presidenteAsociacion
      ? cargoPresidenteAsociacion(_organizacionNombre)
      : cargoPresidenteParada(widget.paradaNombre);

  /// Cargo del "otro" presidente, si su firma se incluye.
  String get _cargoOtro => widget.usuario.rol == UserRole.presidenteAsociacion
      ? cargoPresidenteParada(_paradaNombreActual)
      : cargoPresidenteAsociacion(_organizacionNombre);

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
    _cargarOtroPresidente();
  }

  /// Solo averigua QUIÉN es el otro presidente (id + nombre) para poder
  /// imprimir su cargo debajo del espacio en blanco de firma -- no hace
  /// falta que tenga una firma digital cargada ni aprobada, eso ya no
  /// aplica acá.
  Future<void> _cargarOtroPresidente() async {
    final usuario = widget.usuario;
    final paradaId = _paradaIdActual;
    _paradaIdConsultada = paradaId;
    setState(() => _cargandoOtroPresidente = true);
    try {
      String? otroId;
      String? otroNombre;

      if (paradaId != null) {
        if (usuario.rol == UserRole.presidenteAsociacion) {
          otroId = await _firmaService.obtenerPresidenteParadaId(paradaId);
        } else if (usuario.organizacionId != null) {
          otroId = await _firmaService.obtenerPresidenteAsociacionId(usuario.organizacionId!);
        }
        if (otroId != null) {
          otroNombre = await _firmaService.cargarNombreUsuario(otroId);
        }
      }

      if (!mounted || paradaId != _paradaIdConsultada) return;
      setState(() {
        _otroPresidenteId = otroId;
        _otroPresidenteNombre = otroNombre;
        _incluirFirmaOtro = otroNombre != null;
      });
    } finally {
      if (mounted) setState(() => _cargandoOtroPresidente = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _seleccionadas = {_Columna.nombre, _Columna.cedula};
    _future = widget._todasLasParadas
        ? _service.cargarListadoConductoresOrganizacion(organizacionId: widget.usuario.organizacionId)
        : _service.cargarListadoConductores(widget.paradaId!);
    _cargarOtroPresidente();
    _cargarOrganizacion();
  }

  Future<void> _cargarOrganizacion() async {
    final organizacionId = widget.usuario.organizacionId;
    if (organizacionId == null) return;
    final nombre = await _organizacionService.cargarNombre(organizacionId);
    if (!mounted) return;
    setState(() => _organizacionNombre = nombre);
  }

  Future<void> _generarPdf({bool compartir = false}) async {
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

      // Siempre una sola sección/tabla, sea una parada puntual o "todas
      // las paradas" juntas -- Elias pidió explícitamente que en ese
      // último caso no se separe por hoja (ver _modoBulk).
      final secciones = await _construirSeccionUnica(items);

      final bytes = await _construirPdf(secciones: secciones, columnas: columnas);
      if (compartir) {
        await Printing.sharePdf(bytes: bytes, filename: 'listado_socios.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'listado_socios.pdf');
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  /// Un único listado -- ya sea de una sola parada (o la que sea que el
  /// presidente de parada tiene asignada) o de "todas las paradas"
  /// juntas en una misma tabla (sin separar por hoja, ver _modoBulk).
  /// El bloque de firma es solo cargo + nombre impresos (ver
  /// _construirPdf) -- no depende de ninguna firma digital cargada.
  Future<List<_SeccionListado>> _construirSeccionUnica(List<ConductorListadoItem> items) async {
    final nombreParada = widget._todasLasParadas ? _paradaFiltro : widget.paradaNombre;

    return [
      _SeccionListado(
        subtitulo: nombreParada != null ? 'PARADA Nº ${_tituloParada(nombreParada)}' : null,
        items: items,
        cargoPropio: _incluirFirmaPropia ? _cargoPropio : null,
        nombrePropio: _incluirFirmaPropia ? widget.usuario.nombre : null,
        cargoOtro: (_incluirFirmaOtro && _otroPresidenteNombre != null) ? _cargoOtro : null,
        nombreOtro: (_incluirFirmaOtro && _otroPresidenteNombre != null) ? _otroPresidenteNombre : null,
      ),
    ];
  }

  /// Muchos nombres de parada ya arrancan con la palabra "Parada" (p.
  /// ej. "Parada Km 7", "Parada Microcentro"), así que anteponer
  /// "PARADA Nº" tal cual duplicaba la palabra en el título del PDF
  /// ("PARADA Nº PARADA KM 7"). Acá se saca ese prefijo redundante antes
  /// de armar el subtítulo -- si el nombre no lo tiene, queda igual.
  String _tituloParada(String nombreParada) {
    final sinPrefijo = nombreParada.replaceFirst(RegExp(r'^parada\s+', caseSensitive: false), '').trim();
    return sinPrefijo.isEmpty ? nombreParada : sinPrefijo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Imprimir listado')),
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
                if (_modoBulk) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Se genera un único listado con todos los conductores elegidos, sin separar por parada. '
                    'Sumá la columna "Parada" abajo si querés identificar de dónde es cada uno.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
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
              const SizedBox(height: 4),
              Text(
                'No hace falta firma digital: se imprime el cargo y el nombre con un espacio en blanco arriba '
                'para firmar a mano después de imprimir.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              _SeccionFirmas(
                cargandoOtro: _cargandoOtroPresidente,
                miRolLabel: widget.usuario.rol.label,
                incluirMiFirma: _incluirFirmaPropia,
                onCambiarMiFirma: (valor) => setState(() => _incluirFirmaPropia = valor),
                haySolaParada: _paradaIdActual != null,
                otroRolLabel: _otroRolLabel,
                otroPresidenteNombre: _otroPresidenteNombre,
                incluirOtraFirma: _incluirFirmaOtro,
                onCambiarOtraFirma: _otroPresidenteNombre == null
                    ? null
                    : (valor) => setState(() => _incluirFirmaOtro = valor),
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
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: (_generando || cantidadSeleccionada == 0)
                    ? null
                    : () => _generarPdf(compartir: true),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Compartir PDF'),
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

/// Bloque de selección de firmas a mano: dos casillas, la propia (mi
/// cargo + mi nombre) y la del otro presidente (su cargo + su nombre,
/// si ya sabemos quién es) -- se puede tildar una, la otra, ambas o
/// ninguna. No depende de ninguna firma digital cargada; el PDF deja el
/// espacio en blanco para firmar a mano (ver _construirPdf/bloqueFirma).
class _SeccionFirmas extends StatelessWidget {
  final bool cargandoOtro;
  final String miRolLabel;
  final bool incluirMiFirma;
  final ValueChanged<bool> onCambiarMiFirma;
  final bool haySolaParada;
  final String otroRolLabel;
  final String? otroPresidenteNombre;
  final bool incluirOtraFirma;
  final ValueChanged<bool>? onCambiarOtraFirma;

  const _SeccionFirmas({
    required this.cargandoOtro,
    required this.miRolLabel,
    required this.incluirMiFirma,
    required this.onCambiarMiFirma,
    required this.haySolaParada,
    required this.otroRolLabel,
    required this.otroPresidenteNombre,
    required this.incluirOtraFirma,
    required this.onCambiarOtraFirma,
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
            CheckboxListTile(
              value: incluirMiFirma,
              activeColor: AppTheme.rojoInstitucional,
              title: Text('Mi firma ($miRolLabel)'),
              onChanged: (v) => onCambiarMiFirma(v ?? false),
            ),
            const Divider(height: 1),
            if (cargandoOtro)
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
            else if (otroPresidenteNombre == null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('Todavía no hay $otroRolLabel asignado.', style: subtextStyle),
              )
            else
              CheckboxListTile(
                value: incluirOtraFirma,
                activeColor: AppTheme.rojoInstitucional,
                title: Text('Firma del $otroRolLabel'),
                subtitle: Text(otroPresidenteNombre!),
                onChanged: onCambiarOtraFirma == null ? null : (v) => onCambiarOtraFirma!(v ?? false),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fila de datos para armar un listado: siempre sale una sola
/// [_SeccionListado] en la lista (una sola tabla, un solo membrete, un
/// solo bloque de firma), sea de una parada puntual o de "todas las
/// paradas" juntas -- ver _modoBulk. _construirPdf igual acepta una
/// lista por si en el futuro hiciera falta más de una sección.
/// cargoPropio/cargoOtro son solo texto -- no hay imagen de firma, el
/// PDF deja un espacio en blanco arriba para firmar a mano.
class _SeccionListado {
  final String? subtitulo;
  final List<ConductorListadoItem> items;
  final String? cargoPropio;
  final String? nombrePropio;
  final String? cargoOtro;
  final String? nombreOtro;

  _SeccionListado({
    this.subtitulo,
    required this.items,
    this.cargoPropio,
    this.nombrePropio,
    this.cargoOtro,
    this.nombreOtro,
  });
}

/// ---------------------------------------------------------------------
/// PDF — mismo membrete que ya usa TRAUDE en sus listados en papel
/// (título rojo, texto institucional, franja bandera + logo, "LISTA DE
/// SOCIOS"), más una tabla con numeración de fila y solo las columnas
/// que el presidente eligió — la parada queda identificada como
/// subtítulo del listado, no repetida en cada fila. Si se eligió la
/// columna "Firma", esa celda queda en blanco a propósito para que cada
/// conductor firme a mano después de imprimir. Al final, si se pidió,
/// un bloque con el cargo y el nombre de cada presidente y un espacio
/// en blanco arriba para que firme a mano (no hay imagen de firma
/// digital acá).
/// ---------------------------------------------------------------------

Future<Uint8List> _construirPdf({
  required List<_SeccionListado> secciones,
  required List<_Columna> columnas,
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

  pw.Table tabla(List<ConductorListadoItem> items) {
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
    return pw.Table(
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
    );
  }

  pw.Widget membrete({required String? subtitulo, required int cantidad}) => pw.Column(
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
          pw.Text('Generado el ${formatoFecha.format(DateTime.now())} · $cantidad socios',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 12),
        ],
      );

  // Sin imagen: solo un espacio en blanco arriba de la línea para que
  // la persona firme a mano después de imprimir (pedido de Elias,
  // 2026-08-17 -- no hace falta la firma digital acá).
  pw.Widget bloqueFirma(String cargo, String? nombre) => pw.Column(
        children: [
          pw.SizedBox(height: 46),
          pw.Container(width: 160, height: 0.8, color: PdfColors.grey700),
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

  // Un addPage(MultiPage(...)) por sección, cada una con su propio
  // membrete y bloque de firma al final. OJO: context.pageNumber es
  // GLOBAL a todo el Document (no se reinicia por MultiPage), así que
  // comparar contra 1 solo mostraba el membrete en la primerísima
  // página de TODO el PDF y dejaba en blanco el encabezado de cada
  // sección siguiente (por eso todo el listado parecía pertenecer a la
  // primera parada). Acá se guarda el número de página global que le
  // toca a la PRIMERA página de esta sección en particular (la primera
  // vez que se llama header dentro de este MultiPage) y se compara
  // contra eso, no contra 1 -- así cada sección muestra su propio
  // membrete una sola vez, sin repetirlo en las páginas siguientes de
  // esa misma sección.
  for (final seccion in secciones) {
    final tieneFirmas = seccion.cargoPropio != null || seccion.cargoOtro != null;
    int? primeraPaginaSeccion;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) {
          primeraPaginaSeccion ??= context.pageNumber;
          return context.pageNumber == primeraPaginaSeccion
              ? membrete(subtitulo: seccion.subtitulo, cantidad: seccion.items.length)
              : pw.SizedBox.shrink();
        },
        build: (context) => [
          tabla(seccion.items),
          if (tieneFirmas) ...[
            pw.SizedBox(height: 50),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                if (seccion.cargoPropio != null) bloqueFirma(seccion.cargoPropio!, seccion.nombrePropio),
                if (seccion.cargoOtro != null) bloqueFirma(seccion.cargoOtro!, seccion.nombreOtro),
              ],
            ),
          ],
        ],
      ),
    );
  }

  return doc.save();
}
