library;

import 'camera_permission_status.dart';
import 'camera_permission_io.dart'
    if (dart.library.js_interop) 'camera_permission_web.dart';

export 'camera_permission_status.dart';
export 'camera_permission_io.dart'
    if (dart.library.js_interop) 'camera_permission_web.dart';

/// Asegura el permiso de cámara antes de intentar abrirla.
///
/// Solo actúa en la PWA instalada. En el navegador la cámara ya funciona, y
/// añadir una consulta asíncrona antes de abrir el selector arriesgaría el
/// gesto del usuario que el navegador exige para abrirlo: no se toca lo que
/// no está roto.
Future<CameraGate> ensureCameraAccess() async {
  if (!isInstalledPwa) return CameraGate.ready;

  final status = await cameraAccessStatus();
  if (status == CameraAccess.granted) return CameraGate.ready;

  // `unknown` (Safari) también pasa por aquí: si el permiso ya estaba
  // concedido, `getUserMedia` resuelve sin mostrar ningún diálogo, así que
  // preguntar de más no molesta a nadie.
  final requested = await requestCameraAccess();

  return requested == CameraAccess.granted
      ? CameraGate.justGranted
      : CameraGate.blocked;
}

/// Qué decirle al trabajador cuando el sistema bloquea la cámara.
///
/// El permiso denegado de un WebAPK no se puede volver a pedir desde la
/// aplicación: el diálogo ya no aparece. Sin estas instrucciones el trabajador
/// se queda sin salida.
const String cameraBlockedMessage =
    'La aplicación instalada no tiene permiso de cámara. Ábrelo en '
    'Ajustes de Android → Aplicaciones → InVictor → Permisos → Cámara, '
    'o usa «Elegir archivo».';
