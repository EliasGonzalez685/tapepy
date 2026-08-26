import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../data/perfil_service.dart';
import 'qr_pdf.dart';

/// Vista rápida del código QR, aparte del carnet completo — pensada para
/// mostrar en pantalla sin tener que entrar al carnet entero. El QR
/// codifica la URL pública de verificación (Edge Function
/// `verificar-carnet`): cualquier lector de QR del teléfono la abre
/// directo, sin necesidad de tener la app instalada -- mismo principio
/// que un link de "compartir viaje".
class MiQrScreen extends StatefulWidget {
  final String usuarioId;
  const MiQrScreen({super.key, required this.usuarioId});

  @override
  State<MiQrScreen> createState() => _MiQrScreenState();
}

class _MiQrScreenState extends State<MiQrScreen> {
  final _service = PerfilService();
  late Future<CarnetData> _future;
  bool _compartiendo = false;

  @override
  void initState() {
    super.initState();
    _future = _service.cargarDatosCarnet(widget.usuarioId);
  }

  Future<void> _compartirQr(CarnetData datos) async {
    setState(() => _compartiendo = true);
    try {
      final bytes = await generarPdfQr(datos);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'qr_${datos.nombre.replaceAll(' ', '_')}.pdf',
      );
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi código QR')),
      body: FutureBuilder<CarnetData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('No se pudo cargar: ${snapshot.error}'));
          }
          final datos = snapshot.data!;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: QrImageView(
                      data: SupabaseConfig.urlVerificacionCarnet(datos.qrToken),
                      size: 220,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(datos.nombre,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(datos.rolLabel,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _compartiendo ? null : () => _compartirQr(datos),
                    icon: _compartiendo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_outlined),
                    label: Text(_compartiendo ? 'Generando...' : 'Compartir QR'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

