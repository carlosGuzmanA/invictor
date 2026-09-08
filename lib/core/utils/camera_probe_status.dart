/// Hechos comprobables sobre la cámara en este dispositivo.
///
/// Un fallo de cámara ocurre en el móvil de un trabajador, sin consola del
/// navegador a mano. Sin datos concretos, cada intento de arreglo es una
/// suposición nueva — y ya llevamos varias.
class CameraProbe {
  const CameraProbe({
    required this.installedPwa,
    required this.secureContext,
    required this.permission,
    required this.hasMediaDevices,
    required this.liveCameraWorks,
    required this.liveCameraError,
    required this.platform,
  });

  /// Se ejecuta como PWA instalada (WebAPK en Android).
  final bool installedPwa;

  /// Origen seguro. Sin esto el navegador bloquea la cámara sin avisar.
  final bool secureContext;

  /// Estado según la Permissions API: granted, denied, prompt o unknown.
  final String permission;

  /// El navegador expone `navigator.mediaDevices`.
  final bool hasMediaDevices;

  /// `getUserMedia` consigue abrir la cámara de verdad.
  ///
  /// Es la pregunta que decide el camino: si esto funciona, se puede capturar
  /// sin depender del `<input capture>` que está fallando.
  final bool liveCameraWorks;

  /// Por qué falló `getUserMedia`, si falló.
  final String? liveCameraError;

  /// Navegador y sistema, recortado.
  final String platform;

  /// Resumen de una línea por dato, para leer de un vistazo en el móvil.
  List<String> get lines => [
        'PWA instalada: ${_si(installedPwa)}',
        'Origen seguro: ${_si(secureContext)}',
        'Permiso de cámara: $permission',
        'mediaDevices: ${_si(hasMediaDevices)}',
        'Cámara en vivo: ${_si(liveCameraWorks)}'
            '${liveCameraError == null ? '' : ' — $liveCameraError'}',
        platform,
      ];

  static String _si(bool value) => value ? 'sí' : 'no';
}
