import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../asociacion/data/secretario_service.dart';
import '../../constancia/data/constancia_service.dart';
import '../../constancia/presentation/constancia_pdf.dart';
import '../../firma/data/firma_service.dart';
import '../data/conductor_service.dart';

class _DatosConstancia {
  final ConductorPerfil? perfil;
  final MiSolicitudConstancia? solicitud;
  final SecretarioActual? secretario;
  _DatosConstancia({this.perfil, this.solicitud, this.secretario});
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
  final _secretarioService = SecretarioService();
  late Future<_DatosConstancia> _future;
  bool _solicitando = false;
  bool _generandoPdf = false;
  bool _compartiendoPdf = false;
  // Cofirma opcional del secretario -- solo aparece si la organización
  // tiene uno asignado, y no es obligatorio incluirla igual.
  bool _incluirFirmaSecretario = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _future = _cargarDatos();
  }

  Future<_DatosConstancia> _cargarDatos() async {
    final usuarioId = widget.usuario.id;
    final resultados = await Future.wait([
      _conductorService.cargarPerfil(usuarioId),
      _constanciaService.cargarMiUltimaSolicitud(usuarioId),
    ]);
    final perfil = resultados[0] as ConductorPerfil?;
    SecretarioActual? secretario;
    if (perfil != null) {
      try {
        secretario = await _secretarioService.cargarActual(perfil.organizacionId);
      } catch (_) {
        // Silencioso: si falla, simplemente no se ofrece la cofirma.
      }
    }
    return _DatosConstancia(
      perfil: perfil,
      solicitud: resultados[1] as MiSolicitudConstancia?,
      secretario: secretario,
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

  /// El PDF siempre lleva un solo bloque de firma, el del presidente de
  /// asociación (nunca el de parada) -- pedido explícito de Elias,
  /// 2026-08-17. No hace falta que tenga una firma digital cargada,
  /// alcanza con saber su nombre para imprimirlo debajo del espacio en
  /// blanco donde va a firmar a mano.
  Future<void> _imprimir(String solicitudId) async {
    setState(() => _generandoPdf = true);
    try {
      final datos = await _constanciaService.cargarParaImprimir(solicitudId);

      String? nombreAsociacion;
      final presidenteId = await _firmaService.obtenerPresidenteAsociacionId(datos.organizacionId);
      if (presidenteId != null) {
        nombreAsociacion = await _firmaService.cargarNombreUsuario(presidenteId);
      }

      String? nombreSecretario;
      if (_incluirFirmaSecretario) {
        final secretario = await _secretarioService.cargarActual(datos.organizacionId);
        nombreSecretario = secretario?.nombre;
      }

      final bytes = await construirPdfConstancia(
        datos,
        nombreAsociacion: nombreAsociacion,
        nombreSecretario: nombreSecretario,
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

  Future<void> _compartir(String solicitudId) async {
    setState(() => _compartiendoPdf = true);
    try {
      final datos = await _constanciaService.cargarParaImprimir(solicitudId);

      String? nombreAsociacion;
      final presidenteId = await _firmaService.obtenerPresidenteAsociacionId(datos.organizacionId);
      if (presidenteId != null) {
        nombreAsociacion = await _firmaService.cargarNombreUsuario(presidenteId);
      }

      String? nombreSecretario;
      if (_incluirFirmaSecretario) {
        final secretario = await _secretarioService.cargarActual(datos.organizacionId);
        nombreSecretario = secretario?.nombre;
      }

      final bytes = await construirPdfConstancia(
        datos,
        nombreAsociacion: nombreAsociacion,
        nombreSecretario: nombreSecretario,
      );
      await Printing.sharePdf(bytes: bytes, filename: 'constancia.pdf');
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
                else
                  _ContenidoSolicitud(
                    solicitud: datos.solicitud,
                    solicitando: _solicitando,
                    generandoPdf: _generandoPdf,
                    compartiendoPdf: _compartiendoPdf,
                    secretario: datos.secretario,
                    incluirFirmaSecretario: _incluirFirmaSecretario,
                    onCambiarIncluirSecretario: (v) => setState(() => _incluirFirmaSecretario = v),
                    onSolicitar: () => _solicitar(perfil),
                    onImprimir: (id) => _imprimir(id),
                    onCompartir: (id) => _compartir(id),
                  ),
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
  final bool compartiendoPdf;
  final SecretarioActual? secretario;
  final bool incluirFirmaSecretario;
  final ValueChanged<bool> onCambiarIncluirSecretario;
  final VoidCallback onSolicitar;
  final void Function(String solicitudId) onImprimir;
  final void Function(String solicitudId) onCompartir;

  const _ContenidoSolicitud({
    required this.solicitud,
    required this.solicitando,
    required this.generandoPdf,
    required this.compartiendoPdf,
    required this.secretario,
    required this.incluirFirmaSecretario,
    required this.onCambiarIncluirSecretario,
    required this.onSolicitar,
    required this.onImprimir,
    required this.onCompartir,
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
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Opcional y no obligatorio: solo aparece si la
              // organización tiene un secretario asignado.
              if (secretario != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: incluirFirmaSecretario,
                  activeColor: AppTheme.rojoInstitucional,
                  title: Text('Incluir también la firma del secretario (${secretario!.nombre})'),
                  onChanged: (v) => onCambiarIncluirSecretario(v ?? false),
                ),
              OutlinedButton.icon(
                onPressed: compartiendoPdf ? null : () => onCompartir(solicitud!.id),
                icon: compartiendoPdf
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.share_outlined),
                label: Text(compartiendoPdf ? 'Generando...' : 'Compartir PDF'),
              ),
              TextButton(
                onPressed: solicitando ? null : onSolicitar,
                child: const Text('Solicitar una nueva'),
              ),
            ],
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
