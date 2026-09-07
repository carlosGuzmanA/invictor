import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';
import 'package:invictor/services/realtime_service.dart';

void main() {
  String src(String p) => File(p).readAsStringSync();

  group('presencia', () {
    final service = src('lib/services/presence_service.dart');

    test('publica el estado solo tras confirmarse la suscripción', () {
      // Un `track` antes de que el canal confirme se descarta en el servidor
      // y el usuario nunca aparecería en la lista.
      expect(service, contains('RealtimeSubscribeStatus.subscribed'));
      final trackAt = service.indexOf('channel.track(');
      final statusAt = service.indexOf('RealtimeSubscribeStatus.subscribed');
      expect(statusAt, lessThan(trackAt),
          reason: 'track debe ir dentro del callback de subscribe');
    });

    test('libera el canal al cancelar', () {
      // Sin esto, cambiar de pantalla deja canales abiertos acumulándose.
      expect(service, contains('controller.onCancel'));
      expect(service, contains('untrack()'));
      expect(service, contains('removeChannel'));
    });

    test('deduplica un usuario con varias sesiones', () {
      // Móvil y escritorio abiertos son una persona, no dos.
      expect(service, contains('byProfile'));
      expect(service, contains('devices: existing.devices + 1'));
    });

    test('el texto de la interfaz no promete control de turnos', () {
      final ui = src(
          'lib/features/dashboard/presentation/presence_indicator.dart');
      expect(ui, contains('app abierta'));
      expect(ui.toLowerCase(), isNot(contains('en turno')));
      expect(ui.toLowerCase(), isNot(contains('trabajando')));
    });
  });

  group('tiempo real', () {
    final service = src('lib/services/realtime_service.dart');

    test('agrupa las ráfagas de movimientos', () {
      // Veinte salidas seguidas lanzarían veinte recargas de agregados.
      expect(service, contains('debounce'));
      expect(service, contains('timer?.cancel()'));
    });

    test('el payload se usa como señal, no como dato a mostrar', () {
      // Realtime entrega el registro tal cual se insertó; los datos que se
      // pintan deben salir de las vistas, que filtran por puesto.
      expect(service, contains('RLS'));
      expect(service, contains('removeChannel'));
    });

    test('solo las salidas merecen aviso', () {
      final salida = MovementSignal(
        type: MovementType.salida,
        quantity: 1,
        at: DateTime.now(),
      );
      expect(salida.isWorthAlerting, isTrue);

      for (final t in [
        MovementType.entrada,
        MovementType.ajustePositivo,
        MovementType.devolucion,
      ]) {
        expect(
          MovementSignal(type: t, quantity: 1, at: DateTime.now()).isWorthAlerting,
          isFalse,
          reason: '${t.wireValue} lo registra el propio encargado',
        );
      }
    });

    test('la escucha se limita a staff', () {
      final providers =
          src('lib/features/dashboard/providers/live_providers.dart');
      expect(providers, contains('!profile.isStaff'));
    });
  });

  group('sonido', () {
    test('no se añadió ningún motor de audio', () {
      // audioplayers o just_audio pesarían cientos de KB en una PWA que ya
      // descarga varios megas.
      final pubspec = src('pubspec.yaml');
      for (final pkg in ['audioplayers', 'just_audio', 'audio_session']) {
        expect(pubspec, isNot(contains(pkg)));
      }
    });

    test('viene apagado por defecto', () {
      final providers =
          src('lib/features/dashboard/providers/live_providers.dart');
      expect(providers, contains("getBool(_prefsKey) ?? false"),
          reason: 'un sonido no pedido es una molestia');
    });

    test('un fallo de autoplay no molesta al usuario', () {
      final web = src('lib/core/utils/alert_sound_web.dart');
      expect(web, contains('catch (_)'),
          reason: 'un error en pantalla por un pitido sería peor que el pitido');
    });

    test('en nativo respeta el modo silencio', () {
      final io = src('lib/core/utils/alert_sound_io.dart');
      expect(io, contains('SystemSound.play'));
    });

    test('la interfaz advierte del límite del navegador', () {
      final sheet =
          src('lib/features/dashboard/presentation/live_settings_sheet.dart');
      expect(sheet, contains('kIsWeb'));
      expect(sheet, contains('notificaciones push'),
          reason: 'hay que decir que con la pestaña cerrada no hay aviso');
    });
  });

  group('presencia de todos los roles', () {
    test('existe un tracker que publica sin dibujar nada', () {
      // Un provider de Riverpod no se ejecuta hasta que alguien lo observa:
      // sin este widget, un vendedor nunca se unía al canal y el
      // administrador se veía solo a sí mismo.
      final indicator = src(
          'lib/features/dashboard/presentation/presence_indicator.dart');
      expect(indicator, contains('class PresenceTracker'));
      expect(indicator, contains('SizedBox.shrink()'));
    });

    test('el shell lo monta para cualquier rol', () {
      final shell = src('lib/features/home/presentation/shell_screen.dart');
      expect(shell, contains('PresenceTracker()'));

      // No debe quedar detrás de una condición de rol.
      final at = shell.indexOf('PresenceTracker()');
      final before = shell.substring((at - 200).clamp(0, shell.length), at);
      expect(before, isNot(contains('isStaff')),
          reason: 'un vendedor también tiene que publicar su presencia');
    });
  });

  group('aviso de deshacer', () {
    final undo = src('lib/shared/widgets/undo_snack_bar.dart');

    test('dura cinco segundos', () {
      expect(undo, contains('Duration(seconds: 5)'));
    });

    test('tiene cuenta atrás visible y botón de cerrar', () {
      // Un SnackBar corriente solo admite una acción: con "Deshacer" no
      // quedaba sitio para cerrarlo a mano.
      expect(undo, contains('TweenAnimationBuilder'));
      expect(undo, contains('Icons.close'));
      expect(undo, contains('onClose'));
    });

    test('la barra se agota en el mismo tiempo que el aviso', () {
      expect(undo, contains('duration: UndoSnackBar.duration'),
          reason: 'si no coinciden, la barra miente sobre el tiempo restante');
    });

    test('no apila avisos al encadenar salidas', () {
      expect(undo, contains('hideCurrentSnackBar()'));
    });

    test('la pantalla de productos lo usa', () {
      final tab = src('lib/features/home/presentation/products_tab.dart');
      expect(tab, contains('UndoSnackBar.show'));
      expect(tab, isNot(contains('SnackBarAction')),
          reason: 'el aviso propio reemplaza al SnackBar con acción');
    });
  });

  group('cerrar sesión libera la presencia', () {
    final auth = src('lib/services/auth_service.dart');
    final supabase = src('lib/services/supabase_service.dart');

    test('los canales se cierran ANTES de invalidar el token', () {
      // `signOut` mata el token y el websocket cae con él. Si la salida del
      // canal sale después, no llega al servidor y los demás siguen viendo al
      // usuario conectado hasta que expire el heartbeat.
      final block = RegExp(
        r'Future<void> signOut\(\) async \{([\s\S]*?)\n  \}',
      ).firstMatch(auth);
      expect(block, isNotNull);

      final body = block!.group(1)!;
      final channelsAt = body.indexOf('removeAllChannels');
      final signOutAt = body.indexOf('auth.signOut');

      expect(channelsAt, greaterThan(-1),
          reason: 'signOut debe cerrar los canales de Realtime');
      expect(channelsAt, lessThan(signOutAt),
          reason: 'cerrar los canales después del token llega tarde');
    });

    test('un fallo al cerrar canales no impide salir', () {
      // Nadie debe quedarse atrapado dentro de la app porque falló un canal.
      final block = RegExp(
        r'Future<void> signOut\(\) async \{([\s\S]*?)\n  \}',
      ).firstMatch(auth);
      expect(block!.group(1), contains('catch (_)'));
    });

    test('también se cierran si la sesión expira sola', () {
      // Token vencido, contraseña cambiada o cierre desde otro dispositivo
      // no pasan por signOut.
      expect(supabase, contains('onAuthStateChange.listen'));
      expect(supabase, contains('state.session == null'));
      expect(supabase, contains('removeAllChannels'));

      // Y sobre todo: que el listener se INSTALE. Comprobar solo que el
      // método existe dejaba pasar quitar su llamada, y el guard aprobaba
      // un código que nunca se ejecutaba.
      final init = RegExp(
        r'static Future<void> initialize\(\) async \{([\s\S]*?)\n  \}',
      ).firstMatch(supabase);
      expect(init, isNotNull);
      expect(init!.group(1), contains('_closeChannelsOnSignOut()'),
          reason: 'el listener debe instalarse al arrancar');
    });

    test('desuscribirse tolera un canal ya muerto', () {
      final presence = src('lib/services/presence_service.dart');
      final block = RegExp(
        r'controller\.onCancel = \(\) async \{([\s\S]*?)\n    \};',
      ).firstMatch(presence);
      expect(block, isNotNull);
      expect(block!.group(1), contains('catch (_)'),
          reason: 'untrack sobre un canal cerrado lanza y no debe propagarse');
    });
  });
}
