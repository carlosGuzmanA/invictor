import 'camera_permission_status.dart';

/// En Android/iOS nativos no hay PWA instalada: siempre es la app de verdad.
bool get isInstalledPwa => false;

/// `image_picker` delega en la app de cámara del sistema, que gestiona su
/// propio permiso. No hay nada que consultar desde aquí.
Future<CameraAccess> cameraAccessStatus() async => CameraAccess.granted;

Future<CameraRequest> requestCameraAccess() async =>
    const CameraRequest(CameraAccess.granted);
