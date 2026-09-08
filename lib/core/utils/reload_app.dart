library;

/// Recarga la aplicación descartando la caché del service worker.
///
/// Un `location.reload()` normal puede devolver la versión cacheada: el
/// service worker responde antes de que la petición llegue a la red. Aquí se
/// eliminan las cachés y se anula el registro del worker antes de recargar,
/// para que el navegador vuelva a pedir todo.
export 'reload_app_io.dart'
    if (dart.library.js_interop) 'reload_app_web.dart';
