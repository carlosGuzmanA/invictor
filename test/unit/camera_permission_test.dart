import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/utils/camera_permission.dart';
import 'package:invictor/core/utils/camera_probe.dart';

/// La cámara funciona en Chrome y no hace nada en la PWA instalada. Al
/// instalarla, Chrome genera un WebAPK —una app de Android real— con permisos
/// propios, separados de los del sitio en el navegador. Y
/// `<input type="file" capture>` no pide permiso: si no lo tiene, no abre nada
/// y no avisa.
///
/// Estas pruebas corren en la VM, así que no pueden ejercitar el navegador.
/// Vigilan lo que sí es verificable: que la implementación web siga apoyándose
/// en las llamadas que de verdad disparan el diálogo, y que el camino nativo
/// no se estorbe a sí mismo.
void main() {
  final webSource =
      File('lib/core/utils/camera_permission_web.dart').readAsStringSync();

  group('camino nativo', () {
    test('fuera del navegador nunca es una PWA instalada', () {
      expect(isInstalledPwa, isFalse);
    });

    test('no pide permisos donde el sistema ya los gestiona', () async {
      // En Android/iOS `image_picker` delega en la app de cámara, que pide lo
      // suyo. Interponer otra petición sería un diálogo de más.
      expect((await ensureCameraAccess()).gate, CameraGate.ready);
    });
  });

  group('implementación web', () {
    test('usa getUserMedia, que es lo único que abre el diálogo', () {
      expect(webSource, contains('getUserMedia'),
          reason: '<input capture> no pide permiso; getUserMedia sí');
    });

    test('suelta la cámara después de conseguir el permiso', () {
      // Dejarla encendida gastaría batería y mostraría el indicador de
      // grabación sin motivo.
      expect(webSource, contains('track.stop()'));
    });

    test('detecta la aplicación instalada por display-mode', () {
      expect(webSource, contains('display-mode'));
      expect(webSource, contains('standalone'));
    });

    test('tolera que el navegador no sepa responder', () {
      // Safari no admite consultar `camera` en la Permissions API y lanza.
      // Tratar eso como "denegado" bloquearía la cámara en todos los iPhone.
      expect(webSource, contains('CameraAccess.unknown'));
    });
  });

  group('salida para el trabajador', () {
    test('manda a Chrome, que es donde vive el permiso', () {
      // Un WebAPK no gestiona los permisos de medios: la cámara la controla
      // Chrome por origen. En Ajustes → Aplicaciones → InVictor solo aparece
      // Notificaciones, así que mandar ahí deja al trabajador atascado
      // buscando un permiso que no existe.
      expect(cameraBlockedMessage, contains('Chrome'));
      expect(cameraBlockedMessage, contains('Cámara'));
      expect(cameraBlockedMessage, contains('Elegir archivo'),
          reason: 'debe quedar siempre una vía alternativa');
    });

    test('advierte de que el permiso no está en los ajustes de Android', () {
      expect(cameraBlockedMessage, contains('no está en'));
      expect(cameraBlockedMessage, contains('ajustes de Android'));
    });

    test('un permiso bloqueado conserva el error crudo', () {
      // NotAllowedError, NotFoundError y NotReadableError son tres problemas
      // distintos. "Denegado" a secas no distingue ninguno.
      final source =
          File('lib/core/utils/camera_permission.dart').readAsStringSync();
      expect(source, contains('requested.error'));
    });

    test('conceder el permiso pide un segundo toque, no encadena la captura',
        () {
      final gateDoc =
          File('lib/core/utils/camera_permission_status.dart').readAsStringSync();

      // Tras el diálogo del sistema el navegador ya no considera el toque
      // original un gesto del usuario, así que el selector no abriría.
      expect(CameraGate.values, contains(CameraGate.justGranted));
      expect(gateDoc, contains('gesto'));
    });
  });

  // «No pasa nada al pulsar» no deja rastro: un selector de archivos que no
  // abre no lanza error ni escribe en consola. La sonda es lo único que
  // convierte ese silencio en datos.
  group('sonda de cámara', () {
    final probeSource =
        File('lib/core/utils/camera_probe_web.dart').readAsStringSync();

    test('resume cada hecho en su propia línea', () async {
      final probe = await probeCamera();

      expect(probe.lines, isNotEmpty);
      expect(probe.lines.join('\n'), contains('Permiso de cámara'));
      expect(probe.lines.join('\n'), contains('Cámara en vivo'));
    });

    test('comprueba si getUserMedia funciona de verdad', () {
      // Es la pregunta que decide el camino: si la cámara en vivo abre, se
      // puede capturar sin depender del <input capture> que está fallando.
      expect(probeSource, contains('getUserMedia'));
      expect(probeSource, contains('liveCameraWorks = true'));
    });

    test('conserva el nombre del error de getUserMedia', () {
      // NotAllowedError, NotFoundError y NotReadableError son tres problemas
      // distintos con tres soluciones distintas.
      expect(probeSource, contains('liveCameraError'));
    });

    test('comprueba el origen seguro', () {
      // Sin origen seguro el navegador bloquea la cámara sin avisar.
      expect(probeSource, contains('isSecureContext'));
    });

    test('suelta la cámara después de sondearla', () {
      expect(probeSource, contains('track.stop()'));
    });
  });
}
