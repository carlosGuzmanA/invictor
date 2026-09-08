import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Limpia cachés y service workers, y recarga.
///
/// Sin esto, "Actualizar" podría devolver la misma versión: el service worker
/// intercepta la petición y responde desde su caché. Al anular su registro y
/// borrar las cachés, la recarga vuelve a la red de verdad.
Future<void> reloadApp() async {
  try {
    // 1. Anular el registro de los service workers.
    final sw = web.window.navigator.serviceWorker;
    final regs = await sw.getRegistrations().toDart;
    for (final item in regs.toDart) {
      await item.unregister().toDart;
    }
  } catch (_) {
    // Navegador sin soporte o permiso denegado: se sigue con la recarga.
  }

  try {
    // 2. Borrar las cachés nombradas.
    final caches = web.window.getProperty('caches'.toJS);
    if (caches.isDefinedAndNotNull) {
      final store = caches as web.CacheStorage;
      final keys = await store.keys().toDart;
      for (final key in keys.toDart) {
        await store.delete(key.toDart).toDart;
      }
    }
  } catch (_) {}

  // 3. Recargar. El parámetro fuerza una URL distinta para el navegador.
  final url = web.window.location.href.split('#').first;
  final sep = url.contains('?') ? '&' : '?';
  web.window.location.replace(
    '$url${sep}v=${DateTime.now().millisecondsSinceEpoch}',
  );
}
