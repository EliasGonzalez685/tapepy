import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../constancia/data/constancia_service.dart';
import '../../constancia/presentation/constancia_pdf.dart';
import '../../firma/data/firma_service.dart';
import '../data/conductor_service.dart';

class _DatosConstancia {
  final ConductorPerfil? perfil;
  final MiSolicitudConstancia? solicitud;
  _DatosConstancia({this.perfil, this.solicitud});
}

/// Pantalla del conductor para pedir su constancia (documento formal
/// que certifica que es socio propietario o chofer de una línea de
/// transporte de su parada) y, una vez que el presidente de asociación
/// la aprueba, generarla en PDF con el mismo membrete que el resto de
/// los documentos imprimibles de la app.
class MiConstanciaScreen extends StatefulWidget {
  final Usuario usuario;
  const MiConstanciaScreen({super.key, required this.usuario});

  @override
  State<MiConstanciaScreen> createState() => _MiConstanciaScreenState();
}

class _MiConstanciaScreenState extends State<MiConstanciaScreen> {
  final _conductorService = ConductorService();
  final _constanciaService = ConstanciaService();
  final _firmaService = FirmaService();
  late Future<_DatosConstancia> _future;
  bool _solicitando = false;
  bool _generandoPdf = false;

  // --- Firmas de las autoridades que pueden certificar la constancia:
  // el presidente de asociación (principal) y, si "también" firma, el
  // presidente de la parada del conductor. Mismo mecanismo de
  // solicitud/aprobación que ya usan los listados — acá el conductor es
  // quien solicita, y cada presidente aprueba o rechaza desde "Solicitudes
  // de firma".
  bool _cargandoFirmas = false;
  bool _solicitandoAsociacion = false;
  bool _solicitandoParada = false;

  String? _asociacionId;
  String? _asociacionNombre;
  EstadoFirma _estadoAsociacion = EstadoFirma.ninguna;
  String? _asociacionFirmaPath;
  bool _incluirAsociacion = false;

  String? _paradaPresidenteId;
  String? _paradaPresidenteNombre;
  EstadoFirma _estadoParada = EstadoFirma.ninguna;
  String? _paradaFirmaPath;
  bool _incluirParada = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _cargarDatos();
    _future.then((datos) {
      if (datos.perfil != null) _cargarFirmas(datos.perfil!);
    });
  }

  Future<void> _cargarFirmas(ConductorPerfil perfil) async {
    setState(() => _cargandoFirmas = true);
    try {
      final asociacionId = await _firmaService.obtenerPresidenteAsociacionId(perfil.organizacionId);
      String? asociacionNombre;
      var estadoAsociacion = EstadoFirma.ninguna;
      String? asociacionFirmaPath;
      if (asociacionId != null) {
        asociacionNombre = await _firmaService.cargarNombreUsuario(asociacionId);
        estadoAsociacion = await _firmaService.consultarEstado(
          solicitanteId: widget.usuario.id,
          firmanteId: asociacionId,
          paradaId: perfil.paradaId,
        );
        if (estadoAsociacion == EstadoFirma.aprobada) {
          asociacionFirmaPath = await _firmaService.cargarFirmaUrl(asociacionId);
        }
      }

      final paradaPresidenteId = await _firmaService.obtenerPresidenteParadaId(perfil.paradaId);
      String? paradaNombre;
      var estadoParada = EstadoFirma.ninguna;
      String? paradaFirmaPath;
      if (paradaPresidenteId != null) {
        paradaNombre = await _firmaService.cargarNombreUsuario(paradaPresidenteId);
        estadoParada = await _firmaService.consultarEstado(
          solicitanteId: widget.usuario.id,
          firmanteId: paradaPresidenteId,
          paradaId: perfil.paradaId,
        );
        if (estadoParada == EstadoFirma.aprobada) {
          paradaFirmaPath = await _firmaService.cargarFirmaUrl(paradaPresidenteId);
        }
      }

      if (!mounted) return;
      setState(() {
        _asociacionId = asociacionId;
        _asociacionNombre = asociacionNombre;
        _estadoAsociacion = estadoAsociacion;
        _asociacionFirmaPath = asociacionFirmaPath;
        _incluirAsociacion = estadoAsociacion == EstadoFirma.aprobada && asociacionFirmaPath != null;

        _paradaPresidenteId = paradaPresidenteId;
        _paradaPresidenteNombre = paradaNombre;
        _estadoParada = estadoParada;
        _paradaFirmaPath = paradaFirmaPath;
        // La firma del presidente de parada es adicional ("también"),
        // así que arranca destildada aunque ya esté disponible.
        _incluirParada = false;
      });
    } finally {
      if (mounted) setState(() => _cargandoFirmas = false);
    }
  }

  Future<void> _solicitarFirmaAsociacion() async {
    final perfil = (await _future).perfil;
    if (perfil == null || _asociacionId == null) return;
    setState(() => _solicitandoAsociacion = true);
    try {
      await _firmaService.solicitarFirma(
        organizacionId: perfil.organizacionId,
        paradaId: perfil.paradaId,
        solicitanteId: widget.usuario.id,
        firmanteId: _asociacionId!,
      );
      if (!mounted) return;
      setState(() => _estadoAsociacion = EstadoFirma.pendiente);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se envió la solicitud de firma al Presidente de Asociación')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo enviar la solicitud. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _solicitandoAsociacion = false);
    }
  }

  Future<void> _solicitarFirmaParada() async {
    final perfil = (await _future).perfil;
    if (perfil == null || _paradaPresidenteId == null) return;
    setState(() => _solicitandoParada = true);
    try {
      await _firmaService.solicitarFirma(
        organizacionId: perfil.organizacionId,
        paradaId: perfil.paradaId,
        solicitanteId: widget.usuario.id,
        firmanteId: _paradaPresidenteId!,
      );
      if (!mounted) return;
      setState(() => _estadoParada = EstadoFirma.pendiente);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se envió la solicitud de firma al Presidente de Parada')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo enviar la solicitud. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _solicitandoParada = false);
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

  Future<_DatosConstancia> _cargarDatos() async {
    final usuarioId = widget.usuario.id;
    final resultados = await Future.wait([
      _conductorService.cargarPerfil(usuarioId),
      _constanciaService.cargarMiUltimaSolicitud(usuarioId),
    ]);
    return _DatosConstancia(
      perfil: resultados[0] as ConductorPerfil?,
      solicitud: resultados[1] as MiSolicitudConstancia?,
    );
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    await _future;
  }

  Future<void> _solicitar(ConductorPerfil perfil) async {
    setState(() => _solicitando = true);
    try {
      await _constanciaService.solicitarConstancia(
        organizacionId: perfil.organizacionId,
        paradaId: perfil.paradaId,
        usuarioId: widget.usuario.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud enviada. El presidente de asociación la va a revisar.')),
      );
      await _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo enviar la solicitud. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _solicitando = false);
    }
  }

  Future<void> _imprimir(String solicitudId) async {
    setState(() => _generandoPdf = true);
    try {
      final datos = await _constanciaService.cargarParaImprimir(solicitudId);

      Uint8List? firmaAsociacionBytes;
      if (_incluirAsociacion && _asociacionFirmaPath != null) {
        firmaAsociacionBytes = await _descargarFirma(_asociacionFirmaPath!);
      }
      Uint8List? firmaParadaBytes;
      if (_incluirParada && _paradaFirmaPath != null) {
        firmaParadaBytes = await _descargarFirma(_paradaFirmaPath!);
      }

      final bytes = await construirPdfConstancia(
        datos,
        incluirAsociacion: _incluirAsociacion,
        firmaAsociacionBytes: firmaAsociacionBytes,
        nombreAsociacion: _asociacionNombre,
        incluirParada: _incluirParada,
        firmaParadaBytes: firmaParadaBytes,
        nombreParada: _paradaPresidenteNombre,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'constancia.pdf');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo generar el PDF. Intentá de nuevo.')));
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi constancia')),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<_DatosConstancia>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('No se pudo cargar: ${snapshot.error}')),
                ],
              );
            }
            final datos = snapshot.data!;
            final perfil = datos.perfil;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (perfil == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Todavía no estás asignado a ninguna parada, así que no podés pedir la constancia por ahora.',
                      ),
                    ),
                  )
                else ...[
                  _ContenidoSolicitud(
                    solicitud: datos.solicitud,
                    solicitando: _solicitando,
                    generandoPdf: _generandoPdf,
                    onSolicitar: () => _solicitar(perfil),
                    onImprimir: (id) => _imprimir(id),
                  ),
                  if (datos.solicitud?.estado == 'aprobada') ...[
                    const SizedBox(height: 16),
                    Text('Firmas a incluir', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _SeccionFirmasConstancia(
                      cargando: _cargandoFirmas,
                      asociacionDisponible: _asociacionId != null,
                      asociacionNombre: _asociacionNombre,
                      estadoAsociacion: _estadoAsociacion,
                      asociacionFirmaDisponible: _asociacionFirmaPath != null,
                      incluirAsociacion: _incluirAsociacion,
                      onCambiarAsociacion: (_estadoAsociacion == EstadoFirma.aprobada && _asociacionFirmaPath != null)
                          ? (v) => setState(() => _incluirAsociacion = v)
                          : null,
                      solicitandoAsociacion: _solicitandoAsociacion,
                      onSolicitarAsociacion: _solicitarFirmaAsociacion,
                      paradaDisponible: _paradaPresidenteId != null,
                      paradaNombre: _paradaPresidenteNombre,
                      estadoParada: _estadoParada,
                      paradaFirmaDisponible: _paradaFirmaPath != null,
                      incluirParada: _incluirParada,
                      onCambiarParada: (_estadoParada == EstadoFirma.aprobada && _paradaFirmaPath != null)
                          ? (v) => setState(() => _incluirParada = v)
                          : null,
                      solicitandoParada: _solicitandoParada,
                      onSolicitarParada: _solicitarFirmaParada,
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ContenidoSolicitud extends StatelessWidget {
  final MiSolicitudConstancia? solicitud;
  final bool solicitando;
  final bool generandoPdf;
  final VoidCallback onSolicitar;
  final void Function(String solicitudId) onImprimir;

  const _ContenidoSolicitud({
    required this.solicitud,
    required this.solicitando,
    required this.generandoPdf,
    required this.onSolicitar,
    required this.onImprimir,
  });

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    if (solicitud == null) {
      return _Tarjeta(
        icono: Icons.description_outlined,
        color: AppTheme.rojoInstitucional,
        titulo: 'Solicitar constancia',
        texto: 'Es un documento que certifica que sos socio propietario o chofer de una línea de '
            'transporte de tu parada. Lo aprueba el presidente de asociación.',
        boton: FilledButton(
          onPressed: solicitando ? null : onSolicitar,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
          child: solicitando
              ? const SizedBox(
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Solicitar constancia'),
        ),
      );
    }
    switch (solicitud!.estado) {
      case 'aprobada':
        return _Tarjeta(
          icono: Icons.verified_outlined,
          color: AppTheme.estadoOk,
          titulo: 'Constancia aprobada',
          texto: 'Ya la podés generar en PDF e imprimirla.',
          boton: FilledButton.icon(
            onPressed: generandoPdf ? null : () => onImprimir(solicitud!.id),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.estadoOk),
            icon: generandoPdf
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Generar PDF'),
          ),
          extra: TextButton(
            onPressed: solicitando ? null : onSolicitar,
            child: const Text('Solicitar una nueva'),
          ),
        );
      case 'rechazada':
        return _Tarjeta(
          icono: Icons.cancel_outlined,
          color: AppTheme.estadoUrgente,
          titulo: 'Solicitud rechazada',
          texto: 'El presidente de asociación rechazó tu última solicitud, del '
              '${formatoFecha.format(solicitud!.creadoEn)}. Podés volver a pedirla.',
          boton: FilledButton(
            onPressed: solicitando ? null : onSolicitar,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
            child: solicitando
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Volver a solicitar'),
          ),
        );
      case 'pendiente':
      default:
        return _Tarjeta(
          icono: Icons.hourglass_top_outlined,
          color: AppTheme.estadoAtencion,
          titulo: 'Solicitud pendiente',
          texto: 'Pedida el ${formatoFecha.format(solicitud!.creadoEn)}. El presidente de asociación '
              'todavía no la revisó.',
          boton: null,
        );
    }
  }
}

/// Selector de qué autoridades firman la constancia: el presidente de
/// asociación (principal) y, si "también" corresponde, el presidente de
/// la parada del conductor — cada uno con su propio estado de
/// solicitud/aprobación (ver [FirmaService]).
class _SeccionFirmasConstancia extends StatelessWidget {
  final bool cargando;

  final bool asociacionDisponible;
  final String? asociacionNombre;
  final EstadoFirma estadoAsociacion;
  final bool asociacionFirmaDisponible;
  final bool incluirAsociacion;
  final ValueChanged<bool>? onCambiarAsociacion;
  final bool solicitandoAsociacion;
  final VoidCallback onSolicitarAsociacion;

  final bool paradaDisponible;
  final String? paradaNombre;
  final EstadoFirma estadoParada;
  final bool paradaFirmaDisponible;
  final bool incluirParada;
  final ValueChanged<bool>? onCambiarParada;
  final bool solicitandoParada;
  final VoidCallback onSolicitarParada;

  const _SeccionFirmasConstancia({
    required this.cargando,
    required this.asociacionDisponible,
    required this.asociacionNombre,
    required this.estadoAsociacion,
    required this.asociacionFirmaDisponible,
    required this.incluirAsociacion,
    required this.onCambiarAsociacion,
    required this.solicitandoAsociacion,
    required this.onSolicitarAsociacion,
    required this.paradaDisponible,
    required this.paradaNombre,
    required this.estadoParada,
    required this.paradaFirmaDisponible,
    required this.incluirParada,
    required this.onCambiarParada,
    required this.solicitandoParada,
    required this.onSolicitarParada,
  });

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filaFirma(
              context,
              rolLabel: 'Presidente de Asociación',
              nombre: asociacionNombre,
              disponible: asociacionDisponible,
              estado: estadoAsociacion,
              firmaDisponible: asociacionFirmaDisponible,
              incluir: incluirAsociacion,
              onCambiar: onCambiarAsociacion,
              solicitando: solicitandoAsociacion,
              onSolicitar: onSolicitarAsociacion,
            ),
            const Divider(height: 1),
            _filaFirma(
              context,
              rolLabel: 'Presidente de Parada',
              nombre: paradaNombre,
              disponible: paradaDisponible,
              estado: estadoParada,
              firmaDisponible: paradaFirmaDisponible,
              incluir: incluirParada,
              onCambiar: onCambiarParada,
              solicitando: solicitandoParada,
              onSolicitar: onSolicitarParada,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaFirma(
    BuildContext context, {
    required String rolLabel,
    required String? nombre,
    required bool disponible,
    required EstadoFirma estado,
    required bool firmaDisponible,
    required bool incluir,
    required ValueChanged<bool>? onCambiar,
    required bool solicitando,
    required VoidCallback onSolicitar,
  }) {
    final subtextStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    if (!disponible) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text('Todavía no hay $rolLabel asignado.', style: subtextStyle),
      );
    }
    switch (estado) {
      case EstadoFirma.aprobada when firmaDisponible:
        return CheckboxListTile(
          value: incluir,
          activeColor: AppTheme.rojoInstitucional,
          title: Text(rolLabel),
          subtitle: Text(nombre ?? 'Autorizada'),
          onChanged: onCambiar == null ? null : (v) => onCambiar(v ?? false),
        );
      case EstadoFirma.aprobada:
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Text('El $rolLabel todavía no subió su firma.', style: subtextStyle),
        );
      case EstadoFirma.pendiente:
        return ListTile(
          leading: const Icon(Icons.hourglass_top_outlined, color: Colors.orange),
          title: Text(rolLabel),
          subtitle: const Text('Solicitud de firma pendiente de aprobación'),
        );
      case EstadoFirma.rechazada:
        return ListTile(
          leading: Icon(Icons.block_outlined, color: Theme.of(context).colorScheme.error),
          title: Text(rolLabel),
          subtitle: const Text('Solicitud de firma rechazada'),
          trailing: solicitando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(onPressed: onSolicitar, child: const Text('Reintentar')),
        );
      case EstadoFirma.ninguna:
        return ListTile(
          leading: const Icon(Icons.draw_outlined),
          title: Text(rolLabel),
          subtitle: const Text('Firma no incluida todavía'),
          trailing: solicitando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(onPressed: onSolicitar, child: const Text('Solicitar')),
        );
    }
  }
}

class _Tarjeta extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String texto;
  final Widget? boton;
  final Widget? extra;

  const _Tarjeta({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.texto,
    this.boton,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(icono: icono, color: color, diametro: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(titulo,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(texto,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (boton != null) ...[
              const SizedBox(height: 18),
              boton!,
            ],
            if (extra != null) ...[
              const SizedBox(height: 4),
              extra!,
            ],
          ],
        ),
      ),
    );
  }
}
