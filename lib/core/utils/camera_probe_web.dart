import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'camera_permission.dart';
import 'camera_probe_status.dart';

/// Comprueba en el propio dispositivo qué funciona y qué no.
///
/// Enciende la cámara un instante para saber si `getUserMedia` sirve, y la
/// suelta enseguida. Es intrusivo a propósito: la pregunta que hay que
/// responder es justamente si la cámara se puede abrir.
Future<CameraProbe> probeCamera() async {
  final navigator = web.window.navigator;

  var hasMediaDevices = false;
  var liveCameraWorks = false;
  String? liveCameraError;

  try {
    final media = navigator.mediaDevices;
    hasMediaDevices = true;

    final stream = await media
        .getUserMedia(web.MediaStreamConstraints(video: true.toJS))
        .toDart;
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
    liveCameraWorks = true;
  } catch (e) {
    // El nombre del error es lo que distingue los casos: NotAllowedError es
    // permiso denegado, NotFoundError es que no hay cámara, NotReadableError
    // es que otra aplicación la tiene ocupada.
    liveCameraError = _shorten('$e');
  }

  return CameraProbe(
    installedPwa: isInstalledPwa,
    secureContext: web.window.isSecureContext,
    permission: (await cameraAccessStatus()).name,
    hasMediaDevices: hasMediaDevices,
    liveCameraWorks: liveCameraWorks,
    liveCameraError: liveCameraError,
    platform: _shorten(navigator.userAgent, 120),
  );
}

String _shorten(String text, [int limit = 90]) {
  final clean = text.replaceAll('\n', ' ').trim();
  return clean.length > limit ? '${clean.substring(0, limit)}…' : clean;
}
