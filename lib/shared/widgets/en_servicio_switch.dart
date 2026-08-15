import 'package:flutter/material.dart';
import '../data/estado_servicio_service.dart';

/// Bandera "En servicio" que cada usuario prende o apaga sobre sí
/// mismo — conductores y también los presidentes, de parada y de
/// asociación. Pensado para vivir en el encabezado de cada pantalla
/// home, sobre el fondo rojo institucional.
class EnServicioSwitch extends StatefulWidget {
  final String usuarioId;
  final bool valorInicial;
  const EnServicioSwitch({super.key, required this.usuarioId, required this.valorInicial});

  @override
  State<EnServicioSwitch> createState() => _EnServicioSwitchState();
}

class _EnServicioSwitchState extends State<EnServicioSwitch> {
  final _service = EstadoServicioService();

  // Fuente de verdad compartida en memoria, por usuario. El objeto
  // `usuario` que viaja por la app se captura una sola vez al hacer
  // login (ver app_router.dart) y nunca se refresca, así que cada
  // pantalla nueva construye un EnServicioSwitch con un `valorInicial`
  // potencialmente viejo. Sin este caché, ese widget nuevo pisaba el
  // valor recién tocado por el usuario en otra pantalla, dando la
  // sensación de que la bandera "se cambiaba sola" al navegar. Con el
  // caché, solo el PRIMER switch que se crea para un usuario en toda
  // la sesión fija el valor inicial; el resto simplemente lo comparte.
  static final Map<String, ValueNotifier<bool>> _cache = {};

  late final ValueNotifier<bool> _notifier;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _notifier = _cache.putIfAbsent(widget.usuarioId, () => ValueNotifier(widget.valorInicial));
  }

  Future<void> _cambiar(bool nuevo) async {
    final anterior = _notifier.value;
    _notifier.value = nuevo;
    setState(() => _guardando = true);
    try {
      await _service.actualizar(widget.usuarioId, nuevo);
    } catch (_) {
      _notifier.value = anterior;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar. Intentá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _notifier,
      builder: (context, valor, _) {
        return Container(
          padding: const EdgeInsets.only(left: 10, right: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag, size: 15, color: valor ? Colors.greenAccent : Colors.white54),
              const SizedBox(width: 4),
              Text(
                valor ? 'En servicio' : 'Fuera de servicio',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: valor,
                  onChanged: _guardando ? null : _cambiar,
                  activeColor: Colors.greenAccent,
                  inactiveThumbColor: Colors.white70,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
