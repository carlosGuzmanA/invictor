library;

/// Oculta la pantalla de carga de `web/index.html` una vez que Flutter pintó
/// su primer frame. En plataformas nativas es un no-op.
export 'boot_screen_stub.dart'
    if (dart.library.js_interop) 'boot_screen_web.dart';
