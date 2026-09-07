import 'package:flutter/services.dart';

/// En Android/iOS: sonido del sistema y un toque de vibración.
///
/// El sonido del sistema respeta el modo silencio del teléfono, que es lo que
/// espera cualquiera: nadie quiere que una app le pite con el móvil en
/// silencio dentro de una reunión.
Future<void> playAlertSound() async {
  await SystemSound.play(SystemSoundType.alert);
  await HapticFeedback.mediumImpact();
}

/// En nativo no hay política de autoplay: siempre se puede sonar.
bool get needsUserGesture => false;
