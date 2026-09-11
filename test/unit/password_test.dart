import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/utils/breached_password.dart';
import 'package:invictor/core/utils/password_generator.dart';
import 'package:invictor/core/utils/validators.dart';

/// El aviso de «revisa tus contraseñas» no se puede silenciar desde el sitio:
/// es el navegador comparando la credencial contra listas de filtraciones.
/// Solo desaparece si la contraseña no está en ellas, y la única forma fiable
/// de conseguirlo es no elegirla uno mismo.
void main() {
  group('contraseña generada', () {
    test('es larga y variada', () {
      for (var i = 0; i < 50; i++) {
        final generated = generatePassword();
        expect(generated.length, 18);
        expect(Validators.newPassword(generated), isNull,
            reason: 'la generada debe pasar el propio validador: $generated');
      }
    });

    test('siempre trae las cuatro clases de carácter', () {
      // Dejarlo al azar puro produce de vez en cuando una sin números, y esa
      // la rechazaría el validador justo después de generarla.
      for (var i = 0; i < 50; i++) {
        final generated = generatePassword();
        expect(RegExp(r'[a-z]').hasMatch(generated), isTrue);
        expect(RegExp(r'[A-Z]').hasMatch(generated), isTrue);
        expect(RegExp(r'\d').hasMatch(generated), isTrue);
        expect(RegExp(r'[^\w\s]').hasMatch(generated), isTrue);
      }
    });

    test('evita los caracteres que se confunden al dictarla', () {
      // Se dicta por teléfono a un vendedor más veces de lo que uno quisiera.
      for (var i = 0; i < 50; i++) {
        expect(generatePassword(), isNot(matches(RegExp(r'[lI1O0]'))));
      }
    });

    test('no repite', () {
      final all = {for (var i = 0; i < 200; i++) generatePassword()};
      expect(all.length, 200, reason: 'dos iguales delatarían un azar pobre');
    });

    test('las obligatorias no quedan siempre al principio', () {
      // Sin barajar, los cuatro primeros caracteres seguirían siempre el
      // mismo patrón: minúscula, mayúscula, dígito, símbolo.
      final firstIsLower = List.generate(100, (_) => generatePassword())
          .where((p) => RegExp(r'^[a-z]').hasMatch(p))
          .length;
      expect(firstIsLower, lessThan(90));
    });

    test('usa el azar del sistema, no el predecible', () {
      final source =
          File('lib/core/utils/password_generator.dart').readAsStringSync();
      expect(source, contains('Random.secure()'));
    });
  });

  group('validación de la contraseña nueva', () {
    test('rechaza las más cortas que el mínimo', () {
      expect(Validators.newPassword('Ab1'), isNotNull);
      expect(Validators.newPassword(''), isNotNull);
      expect(Validators.minPasswordLength, 6);
    });

    test('acepta el mínimo justo, con letras y números', () {
      // Bajado de doce a seis a petición del dueño del sistema: exigir doce
      // hacía que nadie cambiara nunca la suya, y una contraseña fuerte que
      // no se usa protege menos que una débil que sí. Lo que sostiene la
      // seguridad pasa a ser el contraste contra filtraciones al guardar.
      expect(Validators.newPassword('zorro9'), isNull);
    });

    test('sigue rechazando una sola clase de carácter', () {
      expect(Validators.newPassword('aaaaaaaaaaaa'), isNotNull);
      expect(Validators.newPassword('zorrito'), isNotNull);
    });

    test('acepta una razonable', () {
      expect(Validators.newPassword('Pelicano#84Kx'), isNull);
    });

    test('la del login no juzga, solo comprueba el mínimo', () {
      // Ahí no se está eligiendo una contraseña: se escribe la que ya existe,
      // y rechazarla sería impedir entrar a quien la tiene bien.
      expect(Validators.password('admin1'), isNull);
      expect(Validators.newPassword('admin1'), isNotNull,
          reason: 'al elegirla sí se mira que no sea una de las filtradas');
    });
  });

  group('la pantalla ayuda al gestor del navegador', () {
    final sheet = File(
      'lib/features/auth/presentation/change_password_sheet.dart',
    ).readAsStringSync();

    test('marca los campos como contraseña nueva', () {
      // Sin esto el gestor no reconoce el formulario y no ofrece guardarla:
      // habría que volver a escribirla en el próximo inicio de sesión.
      expect(sheet, contains('AutofillHints.newPassword'));
      expect(sheet, contains('AutofillGroup('));
    });

    test('avisa al navegador de que el cambio terminó', () {
      expect(sheet, contains('TextInput.finishAutofillContext()'));
    });

    test('la generada se muestra antes de guardarla', () {
      // Ocultar algo que nadie ha memorizado no protege de nada, y sí impide
      // apuntarla.
      expect(sheet, contains('_visible = true'));
    });
  });

  // Longitud y variedad no bastan. `Admin123admin` cumple las dos y está en
  // todas las listas de filtraciones — que es exactamente lo que hace saltar
  // el aviso del navegador que se venía a resolver.
  group('las contraseñas obvias se rechazan aunque sean largas', () {
    test('rechaza las que contienen palabras filtradas', () {
      // La longitud ya no las filtra, así que esta lista es ahora la primera
      // defensa contra lo evidente.
      for (final bad in const [
        'Admin123admin',
        'admin1',
        'clave9',
        'MiPassword2026!',
        'Invictor2026!',
      ]) {
        expect(Validators.newPassword(bad), isNotNull, reason: bad);
      }
    });

    test('rechaza escaleras de dígitos', () {
      expect(Validators.newPassword('Zorro1234Xk!'), isNotNull);
    });

    test('rechaza repeticiones largas', () {
      expect(Validators.newPassword('Zvbnmmmmm9k!'), isNotNull);
    });

    test('acepta una razonable que no cae en ninguna trampa', () {
      expect(Validators.newPassword('Zorro#Verde72'), isNull);
    });
  });

  group('comprobación contra filtraciones reales', () {
    final source =
        File('lib/core/utils/breached_password.dart').readAsStringSync();

    test('la contraseña no sale del dispositivo', () {
      // k-anonimato: se envían cinco caracteres del hash y la comparación se
      // hace aquí. Es lo que hacen Chrome y los gestores de contraseñas.
      expect(source, contains('digest.substring(0, 5)'));
      expect(source, contains('range/\$prefix'));
      expect(source, isNot(contains('body: password')));
    });

    test('pide relleno para no delatar el prefijo por el tamaño', () {
      expect(source, contains("'Add-Padding': 'true'"));
    });

    test('el relleno no se confunde con una coincidencia', () {
      // Las entradas de relleno vienen con recuento 0.
      expect(source, contains('if (count <= 0)'));
    });

    test('no poder comprobar no es lo mismo que estar limpia', () {
      // Sin conexión, bloquear el cambio dejaría a alguien sin poder cambiar
      // una contraseña que el navegador ya está señalando.
      expect(source, contains('BreachCheck.unknown'));
      const desconocido = BreachResult(BreachCheck.unknown);
      expect(desconocido.isBreached, isFalse);
    });
  });

  group('recuperar el acceso', () {
    test('el login ofrece salida a quien olvidó la contraseña', () {
      // El método existía en el servicio desde el principio y nunca se
      // conectó: quien la olvidara se quedaba fuera sin ninguna vía.
      final login = File(
        'lib/features/auth/presentation/login_screen.dart',
      ).readAsStringSync();
      expect(login, contains('¿Olvidaste tu contraseña?'));
      expect(login, contains('sendPasswordReset'));
    });
  });
}
