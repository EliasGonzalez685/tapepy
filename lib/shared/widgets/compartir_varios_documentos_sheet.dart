import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Un documento ya subido, reducido a lo mínimo que hace falta para
/// elegirlo y compartirlo -- así este selector sirve tanto para
/// `DocumentoConductorItem` (Mis documentos) como para `DocumentoItem`
/// (vista de un presidente), sin acoplarse a ninguno de los dos.
typedef DocumentoParaCompartir = ({String id, String etiqueta, String archivoUrl});

/// Deja elegir varios documentos ya subidos, para compartirlos TODOS
/// JUNTOS de una sola vez (por WhatsApp, correo, etc.) -- pedido de
/// Elias 2026-08-22 (3ª vuelta sobre esta idea): la idea anterior era
/// juntar las fotos en una sola hoja nueva, pero eso no terminó de
/// funcionar bien con la librería de PDF.
///
/// Esta hoja SOLO elige documentos -- no descarga ni comparte nada
/// ella misma. Devuelve la lista elegida (o null si se canceló) y es
/// quien la abrió el que hace `compartirVariosDocumentos` después,
/// usando SU PROPIO context. Es importante que sea así: si la
/// descarga/compartir se hacía acá adentro, para cuando terminaba la
/// descarga esta hoja ya estaba cerrada y su context ya no era válido
/// -- el diálogo de "cargando" se quedaba trabado para siempre porque
/// el chequeo `context.mounted` cortaba la función en silencio. Bug
/// real reportado por Elias 2026-08-24: "se queda cargando cuando doy
/// para enviar 2 documentos compartidos".
Future<List<DocumentoParaCompartir>?> mostrarCompartirVariosDocumentosSheet(
  BuildContext context, {
  required List<DocumentoParaCompartir> documentos,
}) {
  return showModalBottomSheet<List<DocumentoParaCompartir>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CompartirVariosDocumentosSheet(documentos: documentos),
  );
}

class _CompartirVariosDocumentosSheet extends StatefulWidget {
  final List<DocumentoParaCompartir> documentos;
  const _CompartirVariosDocumentosSheet({required this.documentos});

  @override
  State<_CompartirVariosDocumentosSheet> createState() => _CompartirVariosDocumentosSheetState();
}

class _CompartirVariosDocumentosSheetState extends State<_CompartirVariosDocumentosSheet> {
  final Set<String> _seleccionados = {};

  void _alternar(String id, bool? valor) {
    setState(() {
      if (valor == true) {
        _seleccionados.add(id);
      } else {
        _seleccionados.remove(id);
      }
    });
  }

  void _confirmar() {
    final elegidos = widget.documentos.where((d) => _seleccionados.contains(d.id)).toList();
    Navigator.of(context).pop(elegidos);
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
                  onChanged: (valor) => _alternar(doc.id, valor),
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
            onPressed: puedeCompartir ? _confirmar : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.rojoInstitucional,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            label: const Text('Compartir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
