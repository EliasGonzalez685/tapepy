import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../utils/imprimir_documento.dart';

/// Un documento ya subido, reducido a lo mínimo que hace falta para
/// elegirlo y compartirlo -- así este selector sirve tanto para
/// `DocumentoConductorItem` (Mis documentos) como para `DocumentoItem`
/// (vista de un presidente), sin acoplarse a ninguno de los dos.
typedef DocumentoParaCompartir = ({String id, String etiqueta, String archivoUrl});

/// Deja elegir varios documentos ya subidos y compartirlos TODOS
/// JUNTOS de una sola vez (por WhatsApp, correo, etc.) -- pedido de
/// Elias 2026-08-22 (3ª vuelta sobre esta idea): la idea anterior era
/// juntar las fotos en una sola hoja nueva, pero eso no terminó de
/// funcionar bien con la librería de PDF. Esto es más simple: cada
/// documento sigue siendo su propio PDF, solo que quien lo recibe los
/// ve todos en el mismo envío en vez de mandarlos uno por uno.
void mostrarCompartirVariosDocumentosSheet(
  BuildContext context, {
  required List<DocumentoParaCompartir> documentos,
  required Future<String> Function(String path) obtenerUrlFirmada,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) =>
        _CompartirVariosDocumentosSheet(documentos: documentos, obtenerUrlFirmada: obtenerUrlFirmada),
  );
}

class _CompartirVariosDocumentosSheet extends StatefulWidget {
  final List<DocumentoParaCompartir> documentos;
  final Future<String> Function(String path) obtenerUrlFirmada;
  const _CompartirVariosDocumentosSheet({required this.documentos, required this.obtenerUrlFirmada});

  @override
  State<_CompartirVariosDocumentosSheet> createState() => _CompartirVariosDocumentosSheetState();
}

class _CompartirVariosDocumentosSheetState extends State<_CompartirVariosDocumentosSheet> {
  final Set<String> _seleccionados = {};
  bool _procesando = false;

  void _alternar(String id, bool? valor) {
    setState(() {
      if (valor == true) {
        _seleccionados.add(id);
      } else {
        _seleccionados.remove(id);
      }
    });
  }

  Future<void> _compartir() async {
    setState(() => _procesando = true);
    final elegidos = widget.documentos.where((d) => _seleccionados.contains(d.id)).toList();
    if (!mounted) return;
    Navigator.of(context).pop();
    await compartirVariosDocumentos(
      context: context,
      obtenerUrlFirmada: widget.obtenerUrlFirmada,
      documentos: elegidos.map((d) => (path: d.archivoUrl, nombreSugerido: d.etiqueta)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final puedeCompartir = _seleccionados.length >= 2;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Compartir varios documentos', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Elegí los documentos que querés mandar juntos (ej. cédula + cédula '
            'verde + habilitación). Cada uno se envía como su propio archivo.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.documentos.length,
              itemBuilder: (context, index) {
                final doc = widget.documentos[index];
                final marcado = _seleccionados.contains(doc.id);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.rojoInstitucional,
                  value: marcado,
                  onChanged: _procesando ? null : (valor) => _alternar(doc.id, valor),
                  title: Text(doc.etiqueta),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Text('${_seleccionados.length} seleccionados (mínimo 2)',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (!puedeCompartir || _procesando) ? null : _compartir,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.rojoInstitucional,
              foregroundColor: Colors.white,
            ),
            icon: _procesando
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.share_outlined, color: Colors.white),
            label: const Text('Compartir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
