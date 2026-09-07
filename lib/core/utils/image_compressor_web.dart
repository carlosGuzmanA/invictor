import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// `image_picker` ignora la compresión en el navegador, así que la hacemos
/// con el canvas: es nativo del navegador y no bloquea el hilo de Dart como
/// haría decodificar el JPEG en Dart puro.
const bool compressesOnDevice = false;

/// Reescala la imagen para que su lado mayor no supere [maxSide] y la
/// recodifica como JPEG con la calidad indicada.
///
/// Si algo falla —formato raro, canvas contaminado, imagen ilegible— devuelve
/// los bytes originales: es preferible subir una foto grande a perder la
/// evidencia de un conteo que el trabajador ya hizo.
Future<Uint8List> compressImage(
  Uint8List bytes, {
  int maxSide = 1600,
  int quality = 80,
}) async {
  String? objectUrl;
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/jpeg'),
    );
    objectUrl = web.URL.createObjectURL(blob);

    final image = await _decode(objectUrl);

    final (width, height) = _fit(image.naturalWidth, image.naturalHeight, maxSide);

    // Ya es lo bastante pequeña: recodificar solo añadiría pérdida.
    if (width == image.naturalWidth &&
        height == image.naturalHeight &&
        bytes.lengthInBytes < 400 * 1024) {
      return bytes;
    }

    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = width
      ..height = height;

    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return bytes;
    ctx.drawImage(image, 0, 0, width, height);

    final dataUrl = canvas.toDataURL('image/jpeg', (quality / 100).toJS);
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return bytes;

    final encoded = base64Decode(dataUrl.substring(comma + 1));

    // Si el resultado no es más pequeño, quedarse con el original.
    return encoded.lengthInBytes < bytes.lengthInBytes ? encoded : bytes;
  } catch (_) {
    return bytes;
  } finally {
    if (objectUrl != null) web.URL.revokeObjectURL(objectUrl);
  }
}

Future<web.HTMLImageElement> _decode(String url) {
  final completer = Completer<web.HTMLImageElement>();
  final image = web.document.createElement('img') as web.HTMLImageElement;

  image.onload = (web.Event _) {
    if (!completer.isCompleted) completer.complete(image);
  }.toJS;

  image.onerror = (web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('No se pudo leer la imagen'));
    }
  }.toJS;

  image.src = url;

  // Una imagen corrupta puede no disparar ni load ni error.
  return completer.future.timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw TimeoutException('Tiempo agotado al leer la imagen'),
  );
}

/// Escala manteniendo la proporción; nunca agranda.
(int, int) _fit(int width, int height, int maxSide) {
  if (width <= 0 || height <= 0) return (width, height);
  final longest = width > height ? width : height;
  if (longest <= maxSide) return (width, height);

  final ratio = maxSide / longest;
  return ((width * ratio).round(), (height * ratio).round());
}
