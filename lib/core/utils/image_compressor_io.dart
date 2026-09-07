import 'dart:typed_data';

/// En Android/iOS `image_picker` ya aplica `maxWidth` e `imageQuality` al
/// capturar, así que no hay nada que recomprimir aquí.
Future<Uint8List> compressImage(
  Uint8List bytes, {
  int maxSide = 1600,
  int quality = 80,
}) async =>
    bytes;

/// El resultado de la captura nativa ya es JPEG.
const bool compressesOnDevice = true;
