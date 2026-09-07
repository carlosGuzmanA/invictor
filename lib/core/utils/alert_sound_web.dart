import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Pitido corto generado con la Web Audio API.
///
/// Dos tonos descendentes: se distingue del ruido ambiente de un centro
/// comercial sin resultar estridente, y no requiere descargar ningún archivo.
///
/// Los navegadores **bloquean el audio hasta que el usuario ha interactuado**
/// con la página (política de autoplay). Si falla por eso, se ignora en
/// silencio: un error en pantalla por un pitido sería peor que el pitido.
Future<void> playAlertSound() async {
  try {
    final ctxCtor = globalContext.getProperty('AudioContext'.toJS) ??
        globalContext.getProperty('webkitAudioContext'.toJS);
    if (ctxCtor == null) return;

    final ctx = (ctxCtor as JSFunction).callAsConstructor<JSObject>();

    // Si el contexto está suspendido por la política de autoplay, se intenta
    // reanudar; si el navegador se niega, no pasa nada más.
    final state = ctx.getProperty('state'.toJS);
    if (state != null && (state as JSString).toDart == 'suspended') {
      ctx.callMethod('resume'.toJS);
    }

    final now = (ctx.getProperty('currentTime'.toJS) as JSNumber).toDartDouble;

    void tone(double startOffset, double frequency, double duration) {
      final osc = ctx.callMethod('createOscillator'.toJS) as JSObject;
      final gain = ctx.callMethod('createGain'.toJS) as JSObject;

      (osc.getProperty('frequency'.toJS) as JSObject)
          .setProperty('value'.toJS, frequency.toJS);
      osc.setProperty('type'.toJS, 'sine'.toJS);

      // Rampa de bajada: un corte seco suena a chasquido.
      final gainValue = gain.getProperty('gain'.toJS) as JSObject;
      gainValue.callMethod(
          'setValueAtTime'.toJS, 0.14.toJS, (now + startOffset).toJS);
      gainValue.callMethod('exponentialRampToValueAtTime'.toJS, 0.0001.toJS,
          (now + startOffset + duration).toJS);

      osc.callMethod('connect'.toJS, gain);
      gain.callMethod(
          'connect'.toJS, ctx.getProperty('destination'.toJS) as JSObject);

      osc.callMethod('start'.toJS, (now + startOffset).toJS);
      osc.callMethod('stop'.toJS, (now + startOffset + duration).toJS);
    }

    tone(0, 880, 0.09);
    tone(0.11, 660, 0.13);
  } catch (_) {
    // Autoplay bloqueado, contexto no disponible o navegador antiguo.
    // No es un fallo que merezca molestar al usuario.
  }
}

/// En web el primer sonido necesita que el usuario haya tocado algo antes.
bool get needsUserGesture => true;
