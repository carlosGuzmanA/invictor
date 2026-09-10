import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un icono nuevo salía en blanco en los dispositivos que ya habían abierto la
/// aplicación, aunque el código llegara bien.
///
/// `assets/` y `canvaskit/` se servían con `max-age=31536000, immutable`, y sus
/// nombres **no llevan hash**: el archivo cambia de contenido conservando la
/// URL. Flutter recorta `MaterialIcons-Regular.otf` en cada compilación para
/// incluir solo los iconos usados, así que el navegador se quedaba un año con
/// una fuente que no contenía los glifos nuevos. Ningún error, ningún aviso:
/// el hueco donde debía ir el icono, y nada más.
///
/// `immutable` solo es correcto cuando la URL cambia al cambiar el contenido.
void main() {
  /// Los comentarios se descartan: el script explica en prosa por qué estos
  /// assets **no** pueden ser inmutables, y esa mención bastaba para dar el
  /// guard por incumplido aunque la configuración fuera correcta.
  String code(String path) => File(path)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('#'))
      .join('\n');

  final deployScript = code('scripts/deploy_static.sh');
  final rootConfig = code('vercel.json');

  /// El `vercel.json` que de verdad se aplica lo escribe el script de
  /// despliegue dentro de la carpeta que sube; el de la raíz solo gobierna el
  /// build remoto. Cambiar uno y olvidar el otro fue parte del problema, así
  /// que se vigilan los dos.
  final sources = {
    'scripts/deploy_static.sh': deployScript,
    'vercel.json': rootConfig,
  };

  group('caché de assets sin hash en el nombre', () {
    test('ninguno se declara inmutable', () {
      for (final entry in sources.entries) {
        expect(
          entry.value,
          isNot(contains('immutable')),
          reason: '${entry.key}: los nombres de los assets de Flutter no '
              'llevan hash, así que su URL no puede prometerse inmutable',
        );
      }
    });

    test('assets y canvaskit revalidan', () {
      for (final entry in sources.entries) {
        for (final path in const ['/assets/(.*)', '/canvaskit/(.*)']) {
          final block = RegExp(
            '${RegExp.escape(path)}[\\s\\S]{0,300}?must-revalidate',
          );
          expect(
            block.hasMatch(entry.value),
            isTrue,
            reason: '${entry.key}: $path debe revalidar, no cachearse a ciegas',
          );
        }
      }
    });

    // Chrome marcó el sitio como engañoso. La causa principal es compartir
    // dominio con miles de sitios en vercel.app, pero un sitio que declara
    // sus cabeceras de seguridad da menos señales de phishing que uno que no
    // declara ninguna — y en cualquier caso son buena práctica.
    test('el sitio declara sus cabeceras de seguridad', () {
      for (final header in const [
        'X-Content-Type-Options',
        'X-Frame-Options',
        'Referrer-Policy',
      ]) {
        expect(deployScript, contains(header),
            reason: 'falta $header en el despliegue');
        expect(rootConfig, contains(header));
      }
    });

    test('la aplicación no se puede embeber en otro sitio', () {
      // Un formulario de contraseña dentro de un iframe ajeno es la forma
      // clásica de robar credenciales, y una señal que Safe Browsing pesa.
      expect(deployScript, contains('"value": "DENY"'));
    });

    test('el índice y el service worker nunca se cachean', () {
      // Si el navegador guarda index.html o el worker, la aplicación no se
      // entera de que hay una versión nueva.
      for (final path in const [
        '/index.html',
        '/flutter_service_worker.js',
        '/flutter_bootstrap.js',
      ]) {
        final block = RegExp(
          '${RegExp.escape(path)}[\\s\\S]{0,300}?no-cache',
        );
        expect(block.hasMatch(deployScript), isTrue,
            reason: '$path no puede quedarse cacheado');
      }
    });
  });
}
