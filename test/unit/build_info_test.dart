import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/config/build_info.dart';
import 'package:invictor/features/home/providers/update_providers.dart';

/// La versión visible existe para responder una pregunta concreta: ¿el
/// teléfono está ejecutando el código nuevo? Con una PWA el service worker
/// sirve lo cacheado y no hay forma de saberlo a simple vista.
void main() {
  String src(String p) => File(p).readAsStringSync();

  group('identidad de la compilación', () {
    test('tiene valores por defecto usables sin dart-define', () {
      // En los tests no hay --dart-define: no debe quedar vacío ni reventar.
      expect(BuildInfo.version, isNotEmpty);
      expect(BuildInfo.commit, isNotEmpty);
      expect(BuildInfo.id, contains('+'));
      expect(BuildInfo.label, startsWith('v'));
    });

    test('distingue una compilación local', () {
      expect(BuildInfo.isLocal, isTrue,
          reason: 'sin BUILD_COMMIT debe reconocerse como local');
    });

    test('una fecha ausente no rompe el parseo', () {
      expect(BuildInfo.builtAtDate, isNull);
    });
  });

  group('el build inyecta y publica la identidad', () {
    final build = src('scripts/vercel_build.sh');

    test('pasa versión, commit y fecha al compilar', () {
      for (final v in ['APP_VERSION', 'BUILD_COMMIT', 'BUILD_TIME']) {
        expect(build, contains('--dart-define=$v='),
            reason: '$v debe inyectarse en el bundle');
      }
    });

    test('escribe build.json DESPUÉS de compilar', () {
      // `flutter build web` limpia el directorio: escribirlo antes lo borraría.
      final buildAt = build.indexOf('"\$FLUTTER" build web');
      final jsonAt = build.indexOf('build/web/build.json');
      expect(buildAt, greaterThan(-1));
      expect(jsonAt, greaterThan(buildAt),
          reason: 'build.json se borraría si se escribe antes del build');
    });

    test('el commit sale de Vercel o de git, con respaldo', () {
      expect(build, contains('VERCEL_GIT_COMMIT_SHA'));
      expect(build, contains('git rev-parse --short HEAD'));
      expect(build, contains('BUILD_COMMIT="local"'));
    });

    test('marca los cambios sin confirmar', () {
      // Para no confundir una prueba local con lo que hay publicado.
      expect(build, contains('-sucio'));
    });
  });

  group('detección de versión nueva', () {
    final checker = src('lib/features/home/providers/update_providers.dart');

    test('la consulta evita la caché', () {
      // Sin esto el service worker devolvería su copia de build.json y la
      // comparación siempre diría que está al día.
      expect(checker, contains('build.json?t='));
      expect(checker, contains('millisecondsSinceEpoch'));
    });

    test('no comprueba en el APK', () {
      // En nativo las actualizaciones se instalan, no se cachean.
      expect(checker, contains('if (!kIsWeb) return null'));
    });

    test('un fallo de red no se confunde con estar al día', () {
      const unknown = UpdateStatus(running: 'a', published: null);
      expect(unknown.unknown, isTrue);
      expect(unknown.hasUpdate, isFalse,
          reason: 'no poder comprobar no es tener una versión nueva');

      const same = UpdateStatus(running: 'a', published: 'a');
      expect(same.hasUpdate, isFalse);
      expect(same.unknown, isFalse);

      const differs = UpdateStatus(running: 'a', published: 'b');
      expect(differs.hasUpdate, isTrue);
    });

    test('no recarga por su cuenta', () {
      // Recargar mientras alguien cuenta un inventario le haría perder lo
      // que está escribiendo.
      final banner = src('lib/features/home/presentation/update_banner.dart');
      expect(banner, contains('onPressed: reloadApp'));
      expect(banner, isNot(contains('addPostFrameCallback')));
    });

    test('la recarga limpia service worker y cachés', () {
      // Un reload normal devolvería la misma versión: el worker responde
      // antes de que la petición llegue a la red.
      final reload = src('lib/core/utils/reload_app_web.dart');
      expect(reload, contains('unregister()'));
      expect(reload, contains('caches'));
      expect(reload, contains('location.replace'));
    });
  });
}
