import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'camera_permission_status.dart';

/// Si la aplicación se está ejecutando como PWA instalada.
///
/// Importa porque al instalarla Chrome genera un WebAPK: una app de Android
/// real, con sus propios permisos, separados de los que el sitio tenga
/// concedidos en el navegador. De ahí que la cámara funcione en Chrome y no
/// haga nada en la aplicación instalada.
bool get isInstalledPwa {
  try {
    for (final mode in const ['standalone', 'fullscreen', 'minimal-ui']) {
      if (web.window.matchMedia('(display-mode: $mode)').matches) return true;
    }
  } catch (_) {
    // matchMedia siempre existe en navegadores reales; si falla, seguimos.
  }

  try {
    // iOS no admite `display-mode` hasta Safari 17: ahí la señal es esta
    // propiedad no estándar de Apple.
    final standalone = web.window.navigator.getProperty('standalone'.toJS);
    if (standalone.isDefinedAndNotNull &&
        (standalone as JSBoolean).toDart) {
      return true;
    }
  } catch (_) {
    // Propiedad ausente: no es iOS instalado.
  }

  return false;
}

/// Consulta el permiso sin molestar al usuario con un diálogo.
Future<CameraAccess> cameraAccessStatus() async {
  try {
    final permissions = web.window.navigator.permissions;

    final descriptor = JSObject()..setProperty('name'.toJS, 'camera'.toJS);
    final status = await permissions.query(descriptor).toDart;

    return switch (status.state) {
      'granted' => CameraAccess.granted,
      'denied' => CameraAccess.denied,
      'prompt' => CameraAccess.prompt,
      _ => CameraAccess.unknown,
    };
  } catch (_) {
    // Safari no admite consultar `camera` en la Permissions API y lanza. No
    // saberlo no es un fallo: se resuelve intentando abrir la cámara.
    return CameraAccess.unknown;
  }
}

/// Pide el permiso mostrando el diálogo del sistema.
///
/// `<input type="file" capture>` **no** pide permiso: si no lo tiene, no abre
/// nada y no avisa. `getUserMedia` es la única llamada que dispara el diálogo,
/// así que se abre la cámara un instante y se suelta enseguida — solo
/// queríamos el permiso, no el vídeo.
Future<CameraRequest> requestCameraAccess() async {
  try {
    final media = web.window.navigator.mediaDevices;
    final stream = await media
        .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
        .toDart;

    // Soltar la cámara de inmediato: dejarla encendida gastaría batería y
    // mostraría el indicador de grabación sin motivo.
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }

    return const CameraRequest(CameraAccess.granted);
  } catch (e) {
    final text = '$e'.replaceAll('\n', ' ').trim();
    return CameraRequest(
      CameraAccess.denied,
      error: text.length > 160 ? '${text.substring(0, 160)}…' : text,
    );
  }
}
