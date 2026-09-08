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
Future<CameraGateResult> ensureCameraAccess() async {
  if (!isInstalledPwa) return const CameraGateResult(CameraGate.ready);

  final status = await cameraAccessStatus();
  if (status == CameraAccess.granted) {
    return const CameraGateResult(CameraGate.ready);
  }

  // `unknown` (Safari) también pasa por aquí: si el permiso ya estaba
  // concedido, `getUserMedia` resuelve sin mostrar ningún diálogo, así que
  // preguntar de más no molesta a nadie.
  final requested = await requestCameraAccess();

  return requested.granted
      ? const CameraGateResult(CameraGate.justGranted)
      : CameraGateResult(
          CameraGate.blocked,
          detail: '[camara/permiso] ${status.name} · ${requested.error}',
        );
}

/// Qué decirle al trabajador cuando el navegador bloquea la cámara.
///
/// **No mandarle a los ajustes de Android.** Un WebAPK no gestiona los
/// permisos de medios: la cámara la controla Chrome por origen, así que en
/// Ajustes → Aplicaciones → InVictor solo aparece Notificaciones. Es
/// exactamente donde se atasca quien busca ahí un permiso que no existe.
const String cameraBlockedMessage =
    'La aplicación instalada no puede abrir la cámara. El permiso no está en '
    'los ajustes de Android: lo controla Chrome. Abre Chrome (el navegador) → '
    'invictor.vercel.app → toca el candado junto a la dirección → Permisos → '
    'Cámara → Permitir. Después vuelve aquí. Mientras tanto puedes usar '
    '«Elegir archivo».';
