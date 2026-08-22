import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';

/// Abre "Tomar foto / Elegir de la galería" y, si el usuario elige una
/// imagen, la deja recortar/ajustar antes de confirmarla -- pedido de
/// Elias 2026-08-22: quería poder corregir la foto si salió mal, no
/// solo descartarla y volver a sacar otra desde cero. Se usa en Mis
/// vehículos y Mis documentos.
///
/// Devuelve null si cancela en cualquier paso (elegir origen, sacar la
/// foto, o el recorte).
Future<XFile?> seleccionarYRecortarFoto(BuildContext context) async {
  final origen = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tomar foto'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (origen == null) return null;

  final elegida = await ImagePicker().pickImage(source: origen, maxWidth: 1600, imageQuality: 85);
  if (elegida == null) return null;

  if (!context.mounted) return elegida;

  final recortada = await ImageCropper().cropImage(
    sourcePath: elegida.path,
    compressQuality: 90,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Ajustar foto',
        toolbarColor: AppTheme.rojoInstitucional,
        toolbarWidgetColor: Colors.white,
        backgroundColor: Colors.black,
        lockAspectRatio: false,
      ),
      IOSUiSettings(
        title: 'Ajustar foto',
        aspectRatioLockEnabled: false,
      ),
    ],
  );
  // Si cancela el recorte, no se pierde la foto original -- se usa tal
  // cual la sacó.
  if (recortada == null) return elegida;
  return XFile(recortada.path);
}
