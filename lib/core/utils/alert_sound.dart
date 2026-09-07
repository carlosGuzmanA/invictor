library;

/// Aviso sonoro de un movimiento, sin dependencias de audio.
///
/// No se añade `audioplayers` ni `just_audio` a propósito: traerían peso a una
/// PWA que ya descarga varios megas, y para un pitido de aviso no hace falta
/// un motor de audio. En web se genera con la Web Audio API —sin archivo— y en
/// Android/iOS se usa el sonido del sistema más vibración.
export 'alert_sound_io.dart'
    if (dart.library.js_interop) 'alert_sound_web.dart';
