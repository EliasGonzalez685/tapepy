import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_theme.dart';
import '../utils/imprimir_documento.dart';

/// Un documento ya subido, reducido a lo mínimo que hace falta para
/// elegirlo y combinarlo -- así este selector sirve tanto para
/// `DocumentoConductorItem` (Mis documentos) como para `DocumentoItem`
/// (vista de un presidente), sin acoplarse a ninguno de los dos.
typedef DocumentoParaCombinar = ({String id, String etiqueta, String archivoUrl});

/// Deja elegir entre 2 y 4 documentos ya subidos y los junta en una
/// sola hoja para ver, imprimir o compartir -- pedido de Elias
/// 2026-08-22: hay documentos que conviene tener juntos (cédula +
/// cédula verde + habilitación, por ejemplo). No borra ni reemplaza
/// nada de lo que ya existe, es una copia extra combinada.
void mostrarCombinarDocumentosSheet(
  BuildContext context, {
  required List<DocumentoParaCombinar> documentos,
  required Future<String> Function(String path) obtenerUrlFirmada,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CombinarDocumentosSheet(documentos: documentos, obtenerUrlFirmada: obtenerUrlFirmada),
  );
}

class _CombinarDocumentosSheet extends StatefulWidget {
  final List<DocumentoParaCombinar> documentos;
  final Future<String> Function(String path) obtenerUrlFirmada;
  const _CombinarDocumentosSheet({required this.documentos, required this.obtenerUrlFirmada});

  @override
  State<_CombinarDocumentosSheet> createState() => _CombinarDocumentosSheetState();
}

class _CombinarDocumentosSheetState extends State<_CombinarDocumentosSheet> {
  static const _maximo = 4;
  final Set<String> _seleccionados = {};
  bool _procesando = false;

  void _alternar(String id, bool? valor) {
    setState(() {
      if (valor == true) {
        if (_seleccionados.length < _maximo) _seleccionados.add(id);
      } else {
        _seleccionados.remove(id);
      }
    });
  }

  Future<List<Uint8List>> _descargarSeleccionados() async {
    final elegidos = widget.documentos.where((d) => _seleccionados.contains(d.id)).toList();
    final resultado = <Uint8List>[];
    for (final doc in elegidos) {
      final url = await widget.obtenerUrlFirmada(doc.archivoUrl);
      final respuesta = await http.get(Uri.parse(url));
      if (respuesta.statusCode != 200) {
        throw Exception('No se pudo descargar ${doc.etiqueta}');
      }
      resultado.add(respuesta.bodyBytes);
    }
    return resultado;
  }

  Future<void> _generar({required bool compartir}) async {
    setState(() => _procesando = true);
    try {
      final pdfs = await _descargarSeleccionados();
      final combinado = await combinarDocumentosEnUnaHoja(pdfs);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (compartir) {
        await compartirBytesPdf(context: context, bytes: combinado, nombreSugerido: 'documentos_combinados.pdf');
      } else {
        await imprimirBytesPdf(context: context, bytes: combinado, nombreSugerido: 'documentos_combinados.pdf');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _procesando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo combinar. Intentá de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final puedeGenerar = _seleccionados.length >= 2 && _seleccionados.length <= _maximo;
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
          Text('Juntar documentos en una hoja', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Elegí entre 2 y 4 documentos para juntarlos en una sola hoja '
            '(ej. cédula + cédula verde + habilitación). Cada documento sigue '
            'existiendo por separado como está ahora.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.documentos.length,
              itemBuilder: (context, index) {
                final doc = widget.documentos[index];
                final marcado = _seleccionados.contains(doc.id);
                final deshabilitado = !marcado && _seleccionados.length >= _maximo;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.rojoInstitucional,
                  value: marcado,
                  onChanged: (_procesando || deshabilitado) ? null : (valor) => _alternar(doc.id, valor),
                  title: Text(doc.etiqueta),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Text('${_seleccionados.length}/$_maximo seleccionados',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (!puedeGenerar || _procesando) ? null : () => _generar(compartir: false),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (!puedeGenerar || _procesando) ? null : () => _generar(compartir: true),
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
              ),
            ],
          ),
        ],
      ),
    );
  }
}
