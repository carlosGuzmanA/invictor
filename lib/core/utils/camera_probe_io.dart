import 'dart:io';

import 'camera_probe_status.dart';

/// En Android/iOS nativos no hay nada que sondear: `image_picker` delega en la
/// app de cámara del sistema.
Future<CameraProbe> probeCamera() async => CameraProbe(
      installedPwa: false,
      secureContext: true,
      permission: 'gestionado por el sistema',
      hasMediaDevices: false,
      liveCameraWorks: false,
      liveCameraError: null,
      platform: Platform.operatingSystem,
    );
