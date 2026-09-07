library;

/// Compresión de fotografías antes de subirlas a Storage (§18).
///
/// Hace falta una implementación propia para web porque `image_picker`
/// **ignora en silencio** `maxWidth`, `maxHeight` e `imageQuality` en el
/// navegador (así lo documenta `image_picker_for_web`). Como el iPhone entra
/// por PWA (§13), sin esto cada foto subiría a tamaño completo —3–5 MB del
/// carrete de un iPhone— consumiendo los datos móviles del trabajador y
/// llenando el bucket.
///
/// En Android/iOS nativos `image_picker` sí comprime al capturar, así que la
/// implementación nativa devuelve los bytes tal cual.
export 'image_compressor_io.dart'
    if (dart.library.js_interop) 'image_compressor_web.dart';
