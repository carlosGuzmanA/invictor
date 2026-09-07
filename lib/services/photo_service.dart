import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/image_compressor.dart';

/// Captura de fotografías para los conteos (§14).
///
/// En Android/iOS nativos usa la cámara del dispositivo. En web —el caso del
/// iPhone vía PWA— `image_picker` se traduce a
/// `<input type="file" accept="image/*" capture="environment">`, que abre la
/// cámara trasera en Safari y Chrome móvil.
class PhotoService {
  const PhotoService();

  /// Devuelve los bytes ya comprimidos, o null si el usuario canceló.
  ///
  /// Cancelar no es un error: el trabajador puede arrepentirse y no debe ver
  /// un mensaje de fallo por ello.
  Future<CapturedPhoto?> capture({
    ImageSource source = ImageSource.camera,
  }) async {
    // En web, ImageSource.camera se traduce a `capture="environment"`, que en
    // Safari y Chrome móvil abre la cámara trasera; en escritorio abre el
    // selector de archivos. ImageSource.gallery abre siempre el selector.
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        // En nativo esto ya comprime. En web se ignora en silencio, por eso
        // después pasa siempre por `compressImage`.
        maxWidth: AppConstants.photoMaxWidth,
        maxHeight: AppConstants.photoMaxHeight,
        imageQuality: AppConstants.photoQuality,
      );
      if (file == null) return null;

      final original = await file.readAsBytes();
      final bytes = await compressImage(
        original,
        maxSide: AppConstants.photoMaxWidth.round(),
        quality: AppConstants.photoQuality,
      );

      if (bytes.lengthInBytes > AppConstants.photoMaxBytes) {
        throw const AppException(
          'La fotografía sigue siendo demasiado grande incluso comprimida. '
          'Prueba con menos resolución en la cámara.',
        );
      }

      return CapturedPhoto(
        bytes: bytes,
        originalBytes: original.lengthInBytes,
        contentType: 'image/jpeg',
      );
    } on AppException {
      rethrow;
    } catch (e, s) {
      // El caso más común aquí es permiso de cámara denegado.
      throw mapError(
        const AppException(
          'No se pudo acceder a la cámara. Revisa los permisos del navegador '
          'o de la aplicación.',
        ),
        s,
      );
    }
  }
}

class CapturedPhoto {
  const CapturedPhoto({
    required this.bytes,
    required this.originalBytes,
    required this.contentType,
  });

  final Uint8List bytes;
  final int originalBytes;
  final String contentType;

  int get sizeKb => (bytes.lengthInBytes / 1024).round();

  /// Cuánto se redujo, para poder comprobar que la compresión hace algo.
  double get reduction => originalBytes == 0
      ? 0
      : 1 - (bytes.lengthInBytes / originalBytes);
}
