import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/user_role.dart';
import '../../../shared/models/usuario.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../data/parada_detalle_service.dart';

/// Listado de vencimiento de carnet de los socios: una sola parada
/// (presidente de esa parada, pasa [paradaId]) o toda la organización
/// (presidente de asociación / dueño de plataforma, que reusa esta
/// misma pantalla sin [paradaId] -- ver AsociacionHomeScreen). La
/// renovación queda en manos de los presidentes correspondientes o del
/// dueño de plataforma, nunca del propio socio (pedido de Elias,
/// 2026-08-16): cada uno ve su propia fecha en Datos personales, pero
/// sin poder tocarla.
class VencimientosCarnetScreen extends StatefulWidget {
  final Usuario? usuario;
  final String? paradaId;
  final String? paradaNombre;
  const VencimientosCarnetScreen({
    super.key,
    required this.usuario,
    this.paradaId,
    this.paradaNombre,
  });

  bool get _todaLaOrganizacion => paradaId == null;

  @override
  State<VencimientosCarnetScreen> createState() => _VencimientosCarnetScreenState();
}

class _VencimientosCarnetScreenState extends State<VencimientosCarnetScreen> {
  final _service = ParadaDetalleService();
  late Future<List<SocioCarnetItem>> _future;
  final _formatoFecha = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<List<SocioCarnetItem>> _cargar() {
    if (widget.paradaId != null) {
      return _service.cargarVencimientosCarnet(widget.paradaId!);
    }
    return _service.cargarVencimientosCarnetOrganizacion(
      organizacionId: widget.usuario?.organizacionId,
    );
  }

  Future<void> _refrescar() async {
    setState(() => _future = _cargar());
    await _future;
  }

  /// Refleja la misma regla que la RLS (migración 0021): los
  /// presidentes solo pueden renovar filas rol='conductor' que no sean
  /// la propia; el dueño de plataforma no tiene esa restricción. Evita
  /// mostrar un botón que Postgres va a rechazar igual.
  bool _puedeRenovar(SocioCarnetItem item) {
    final viewer = widget.usuario;
    if (viewer == null) return false;
    if (viewer.rol == UserRole.duenoPlataforma) return true;
    if (item.usuarioId == viewer.id) return false;
    return item.rol == 'conductor';
  }

  _Estado _estadoDe(DateTime? vencimiento) {
    if (vencimiento == null) return _Estado.sinGenerar;
    final hoy = DateTime.now();
    final dias = vencimiento.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
    if (dias < 0) return _Estado.vencido;
    if (dias <= 60) return _Estado.porVencer;
    return _Estado.vigente;
  }

  Future<void> _renovar(SocioCarnetItem item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renovar carnet'),
        content: Text('¿Renovar el carnet de ${item.nombre} por 1 año más desde hoy?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.rojoInstitucional),
            child: const Text('Renovar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _service.renovarCarnet(item.usuarioId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Carnet de ${item.nombre} renovado por 1 año')));
      _refrescar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo renovar. Intentá de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget._todaLaOrganizacion
              ? 'Vencimientos de carnet'
              : 'Vencimientos · ${widget.paradaNombre ?? ''}',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<SocioCarnetItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudo cargar: ${snapshot.error}'),
                  ),
                ],
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(Icons.credit_card_outlined,
                            size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text('Todavía no hay socios para mostrar.', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              );
            }
            final vencidos = items.where((i) => _estadoDe(i.carnetVencimiento) == _Estado.vencido).length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (vencidos > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.estadoUrgente.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_outlined, color: AppTheme.estadoUrgente, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$vencidos carnet${vencidos == 1 ? '' : 's'} vencido${vencidos == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                ...items.map((item) => _SocioCarnetCard(
                      item: item,
                      estado: _estadoDe(item.carnetVencimiento),
                      formatoFecha: _formatoFecha,
                      mostrarParada: widget._todaLaOrganizacion,
                      puedeRenovar: _puedeRenovar(item),
                      onRenovar: () => _renovar(item),
                    )),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _Estado { vigente, porVencer, vencido, sinGenerar }

extension on _Estado {
  Color get color {
    switch (this) {
      case _Estado.vigente:
        return AppTheme.estadoOk;
      case _Estado.porVencer:
        return AppTheme.estadoAtencion;
      case _Estado.vencido:
        return AppTheme.estadoUrgente;
      case _Estado.sinGenerar:
        return Colors.grey;
    }
  }

  String get etiqueta {
    switch (this) {
      case _Estado.vigente:
        return 'Vigente';
      case _Estado.porVencer:
        return 'Por vencer';
      case _Estado.vencido:
        return 'Vencido';
      case _Estado.sinGenerar:
        return 'Sin generar';
    }
  }
}

class _SocioCarnetCard extends StatelessWidget {
  final SocioCarnetItem item;
  final _Estado estado;
  final DateFormat formatoFecha;
  final bool mostrarParada;
  final bool puedeRenovar;
  final VoidCallback onRenovar;

  const _SocioCarnetCard({
    required this.item,
    required this.estado,
    required this.formatoFecha,
    required this.mostrarParada,
    required this.puedeRenovar,
    required this.onRenovar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(icono: Icons.credit_card_outlined, color: estado.color, diametro: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.nombre,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (mostrarParada && item.paradaNombre != null) item.paradaNombre!,
                      item.carnetVencimiento != null
                          ? 'Vence ${formatoFecha.format(item.carnetVencimiento!)}'
                          : 'Todavía no generó su carnet',
                    ].join(' · '),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: estado.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estado.etiqueta,
                      style: TextStyle(color: estado.color, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (puedeRenovar)
              TextButton(
                onPressed: onRenovar,
                style: TextButton.styleFrom(foregroundColor: AppTheme.rojoInstitucional),
                child: const Text('Renovar'),
              ),
          ],
        ),
      ),
    );
  }
}
