import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Llama a `window.dismissBootScreen()`, definido en `web/index.html`.
void dismissBootScreen() {
  if (globalContext.has('dismissBootScreen')) {
    globalContext.callMethod('dismissBootScreen'.toJS);
  }
}
