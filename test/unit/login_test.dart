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

  group('el aviso no mueve los campos', () {
    test('el formulario va anclado arriba, no centrado', () {
      // Centrado, aparecer el aviso lo recolocaba entero y los dos campos
      // subían 31 px. En un móvil eso pasa mientras el dedo va de camino: se
      // toca donde estaba el campo, no donde está. Medido, no supuesto.
      expect(codigo, contains('Alignment.topCenter'));
      expect(
        codigo,
        isNot(contains('child: Center(')),
        reason: 'Volver a centrar el formulario hace que el aviso lo desplace.',
      );
    });
  });

  group('tras fallar, se puede reintentar', () {
    test('el foco se suelta, no se pide', () {
      // Se probó pedirlo y fue peor: Chrome de Android no abre el teclado
      // cuando el foco lo pide el programa en vez del dedo, así que el campo
      // quedaba marcado como enfocado con el teclado cerrado. A partir de ahí
      // tocarlo ya no era un cambio de foco y no pedía teclado.
      expect(codigo, contains('_passwordFocus.unfocus()'));
      expect(
        codigo,
        isNot(contains('_passwordFocus.requestFocus()')),
        reason: 'Pedir el foco por código deja el campo muerto en Android.',
      );
      expect(codigo, contains('focusNode: _passwordFocus'));
      expect(codigo, contains('_prepararReintento'));
    });

    test('el foco se pide después del fotograma, no durante', () {
      // Pedirlo mientras la pantalla se está reconstruyendo no llega a ninguna
      // parte: el campo todavía no existe cuando se pide.
      expect(codigo, contains('addPostFrameCallback'));
    });

    test('la contraseña que no valía se borra', () {
      // Dejarla escrita y solo seleccionada no se sostiene: al tocar el campo
      // el toque coloca el cursor y deshace la selección, así que lo siguiente
      // se pega detrás. El segundo intento salía con las dos juntas.
      expect(codigo, contains('_passwordCtrl.clear()'));
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
