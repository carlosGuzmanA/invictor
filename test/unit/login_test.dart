import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El acceso tiene que aguantar que alguien se equivoque.
///
/// Escribiendo mal la contraseña salía el aviso y, a partir de ahí, el campo
/// dejaba de responder: en la aplicación instalada en Android tocarlo ni
/// siquiera abría el teclado. Quien fallaba una vez se quedaba fuera hasta
/// recargar la página.
///
/// El recorrido con navegador de verdad está en `scripts/e2e/acceso.mjs` y es
/// el que comprueba el comportamiento. Esto de aquí fija las dos decisiones
/// del código que lo sostienen, para que no se deshagan al editar la pantalla
/// sin saber por qué estaban puestas.
void main() {
  // Sin las líneas de comentario: sus explicaciones mencionan justo lo que se
  // busca, y la comprobación pasaría por el texto que la describe en vez de
  // por el código. Ya ocurrió antes en este proyecto.
  final codigo = File('lib/features/auth/presentation/login_screen.dart')
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('los campos no desaparecen mientras se comprueba', () {
    test('se bloquean en solo lectura, no se deshabilitan', () {
      // Un campo deshabilitado deja de existir en la página mientras dura el
      // envío, y al rehabilitarse es otro campo distinto. En Chrome de Android
      // ese cambiazo bastaba para que el teclado ya no se abriera.
      expect(codigo, isNot(contains('enabled: !_busy')));
      expect(
        RegExp('readOnly: _busy').allMatches(codigo).length,
        2,
        reason: 'Los dos campos deben quedar en solo lectura durante el envío.',
      );
    });
  });

  group('tras fallar, se puede reintentar sin tocar nada', () {
    test('el cursor vuelve solo al campo de contraseña', () {
      expect(codigo, contains('_passwordFocus'));
      expect(codigo, contains('focusNode: _passwordFocus'));
      expect(codigo, contains('_prepararReintento'));
    });

    test('el foco se pide después del fotograma, no durante', () {
      // Pedirlo mientras la pantalla se está reconstruyendo no llega a ninguna
      // parte: el campo todavía no existe cuando se pide.
      expect(codigo, contains('addPostFrameCallback'));
    });

    test('lo que se teclee reemplaza la contraseña fallida', () {
      // Sin seleccionar lo anterior, el segundo intento sale con la contraseña
      // vieja pegada delante y vuelve a fallar, ahora sin motivo aparente.
      expect(codigo, contains('TextSelection('));
      expect(codigo, contains('_passwordCtrl.text.length'));
    });

    test('solo se prepara el reintento cuando de verdad hubo un fallo', () {
      // Si se pidiera el foco siempre, saltaría también al entrar bien, justo
      // cuando la pantalla se está yendo.
      expect(codigo, contains('if (_error != null)'));
    });

    test('el foco se libera al cerrar la pantalla', () {
      expect(codigo, contains('_passwordFocus.dispose()'));
    });
  });
}
