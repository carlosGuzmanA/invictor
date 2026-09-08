/// Estado del permiso de cámara del navegador.
enum CameraAccess {
  /// El permiso está concedido: la cámara se puede abrir.
  granted,

  /// El usuario (o el sistema) lo denegó. No se puede volver a pedir desde
  /// la aplicación: hay que abrirlo en los ajustes.
  denied,

  /// Todavía no se ha decidido. Pedirlo mostrará el diálogo del sistema.
  prompt,

  /// El navegador no sabe responder. Safari, por ejemplo, no admite consultar
  /// `camera` en la Permissions API: la única forma de saberlo es intentarlo.
  unknown,
}

/// Resultado de pedir el permiso, con el error crudo si lo hubo.
///
/// El nombre del error es lo que distingue los casos: `NotAllowedError` es
/// permiso denegado, `NotFoundError` es que no hay cámara y
/// `NotReadableError` es que otra aplicación la tiene ocupada. Tirarlo y
/// mostrar solo "denegado" deja al usuario —y a quien depura— sin nada.
class CameraRequest {
  const CameraRequest(this.access, {this.error});

  final CameraAccess access;
  final String? error;

  bool get granted => access == CameraAccess.granted;
}

/// Qué hacer antes de abrir la cámara, y por qué.
class CameraGateResult {
  const CameraGateResult(this.gate, {this.detail});

  final CameraGate gate;

  /// Error crudo, para mostrar bajo el mensaje.
  final String? detail;
}

/// Qué hacer antes de abrir la cámara.
enum CameraGate {
  /// Adelante: no hace falta pedir nada.
  ready,

  /// Se acaba de conceder el permiso.
  ///
  /// Conviene no encadenar la captura aquí: entre medias hubo un diálogo del
  /// sistema, y el navegador ya no considera el toque original como un gesto
  /// del usuario, así que el selector de archivos no abriría. Es más fiable
  /// pedir un segundo toque que abrir nada.
  justGranted,

  /// El permiso está denegado y solo se puede cambiar desde los ajustes del
  /// sistema.
  blocked,
}
