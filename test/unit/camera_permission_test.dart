import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/utils/camera_permission.dart';

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
      expect(await ensureCameraAccess(), CameraGate.ready);
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
    test('un permiso denegado explica dónde se cambia', () {
      // El diálogo del sistema ya no vuelve a aparecer: sin instrucciones el
      // trabajador se queda sin forma de continuar.
      expect(cameraBlockedMessage, contains('Ajustes'));
      expect(cameraBlockedMessage, contains('Permisos'));
      expect(cameraBlockedMessage, contains('Elegir archivo'),
          reason: 'debe quedar siempre una vía alternativa');
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
}
