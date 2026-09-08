import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/image_compressor.dart';

/// En qué paso de la captura falló algo.
///
/// Antes un único `catch` envolvía los tres pasos y siempre culpaba a los
/// permisos de la cámara. Cuando el fallo real era otro —el navegador no
/// devolvió el archivo, la imagen no se pudo leer— el mensaje mandaba a
/// revisar donde no estaba el problema y costaba horas encontrarlo.
enum PhotoStage {
  /// Abrir la cámara o el selector de archivos.
  pick('camara/abrir'),

  /// Leer los bytes del archivo que devolvió el navegador.
  read('camara/leer'),

  /// Reescalar y recodificar la imagen.
  compress('camara/comprimir'),

  /// La imagen sigue pesando de más incluso comprimida.
  size('camara/tamano');

  const PhotoStage(this.code);

  final String code;
}

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
  ///
  /// Con [ImageSource.gallery] se abre el selector de archivos sin el atributo
  /// `capture`. Es la vía de escape cuando la cámara directa falla: en Android
  /// el propio selector ofrece la cámara, así que el trabajador puede seguir
  /// trabajando aunque el camino corto esté roto.
  Future<CapturedPhoto?> capture({
    ImageSource source = ImageSource.camera,
  }) async {
    final XFile? file;
    try {
      final picker = ImagePicker();
      file = await picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        // En nativo esto ya comprime. En web se ignora en silencio, por eso
        // después pasa siempre por `compressImage`.
        maxWidth: AppConstants.photoMaxWidth,
        maxHeight: AppConstants.photoMaxHeight,
        imageQuality: AppConstants.photoQuality,
      );
    } catch (e) {
      throw _fail(
        PhotoStage.pick,
        source == ImageSource.camera
            ? 'No se pudo abrir la cámara. Revisa que el navegador tenga '
                  'permiso de cámara para este sitio, o prueba con '
                  '«Elegir archivo».'
            : 'No se pudo abrir el selector de archivos.',
        e,
      );
    }

    if (file == null) return null;

    final Uint8List original;
    try {
      original = await file.readAsBytes();
    } catch (e) {
      throw _fail(
        PhotoStage.read,
        'La fotografía se tomó pero no se pudo leer del dispositivo. '
        'Inténtalo de nuevo.',
        e,
      );
    }

    // `compressImage` está escrito para no lanzar nunca —ante cualquier fallo
    // devuelve los bytes originales, porque subir una foto grande es mejor que
    // perder la evidencia de un conteo ya hecho. El catch cubre lo imprevisto.
    final Uint8List bytes;
    try {
      bytes = await compressImage(
        original,
        maxSide: AppConstants.photoMaxWidth.round(),
        quality: AppConstants.photoQuality,
      );
    } catch (e) {
      throw _fail(
        PhotoStage.compress,
        'No se pudo procesar la fotografía en este navegador.',
        e,
      );
    }

    if (bytes.lengthInBytes > AppConstants.photoMaxBytes) {
      throw AppException(
        'La fotografía sigue siendo demasiado grande incluso comprimida '
        '(${(bytes.lengthInBytes / 1024).round()} KB). '
        'Prueba con menos resolución en la cámara.',
        code: PhotoStage.size.code,
      );
    }

    return CapturedPhoto(
      bytes: bytes,
      originalBytes: original.lengthInBytes,
      contentType: 'image/jpeg',
    );
  }
}

/// Conserva el error crudo en `cause` y la etapa en `code`.
///
/// Sin el error crudo, diagnosticar un fallo de cámara en el teléfono de un
/// trabajador —sin consola del navegador a mano— es adivinar.
AppException _fail(PhotoStage stage, String message, Object error) =>
    AppException(message, code: stage.code, cause: error);

/// Texto técnico corto para mostrar bajo el mensaje al usuario.
///
/// Devuelve null si no hay nada que añadir, para no ensuciar la interfaz
/// cuando el error ya se explica solo.
String? technicalDetail(AppException e) {
  final cause = e.cause;
  if (cause == null) return null;

  final text = '${cause.runtimeType}: $cause'.replaceAll('\n', ' ').trim();
  const limit = 240;
  final trimmed = text.length > limit ? '${text.substring(0, limit)}…' : text;

  return e.code == null ? trimmed : '[${e.code}] $trimmed';
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
