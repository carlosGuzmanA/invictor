import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/alert_sound.dart';
import '../../../services/presence_service.dart';
import '../../../services/realtime_service.dart';
import '../../../services/service_providers.dart';

/// Usuarios con la aplicación abierta. Lista vacía si no hay sesión.
final onlineUsersProvider = StreamProvider<List<OnlineUser>>((ref) async* {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) {
    yield const [];
    return;
  }
  yield* ref.watch(presenceServiceProvider).watch(profile);
});

/// Preferencia de aviso sonoro, recordada en el dispositivo.
///
/// Por defecto **apagada**: un sonido que aparece sin haberlo pedido es una
/// molestia, y el administrador puede tener el dashboard abierto todo el día.
class SoundAlertsNotifier extends AsyncNotifier<bool> {
  static const _prefsKey = 'sound_alerts_enabled';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = AsyncData(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);

    // Al activarlo suena una vez: confirma que funciona y, en web, aprovecha
    // el toque del interruptor para desbloquear el audio del navegador.
    if (value) await playAlertSound();
  }
}

final soundAlertsProvider =
    AsyncNotifierProvider<SoundAlertsNotifier, bool>(SoundAlertsNotifier.new);

/// Señal de movimientos en vivo. Solo se activa para staff: un vendedor no
/// necesita enterarse de lo que registran los demás.
final movementSignalProvider =
    StreamProvider.autoDispose<MovementSignal>((ref) async* {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null || !profile.isStaff) return;
  yield* ref.watch(realtimeServiceProvider).watchMovements();
});
