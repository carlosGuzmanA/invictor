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
        final password = generatePassword();
        expect(password.length, 18);
        expect(Validators.newPassword(password), isNull,
            reason: 'la generada debe pasar el propio validador: $password');
      }
    });

    test('siempre trae las cuatro clases de carácter', () {
      // Dejarlo al azar puro produce de vez en cuando una sin números, y esa
      // la rechazaría el validador justo después de generarla.
      for (var i = 0; i < 50; i++) {
        final password = generatePassword();
        expect(RegExp(r'[a-z]').hasMatch(password), isTrue);
        expect(RegExp(r'[A-Z]').hasMatch(password), isTrue);
        expect(RegExp(r'\d').hasMatch(password), isTrue);
        expect(RegExp(r'[^\w\s]').hasMatch(password), isTrue);
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
    test('rechaza las cortas', () {
      // Supabase acepta seis, pero las cortas están todas en las listas de
      // filtraciones y el aviso volvería a salir el mismo día.
      expect(Validators.newPassword('Abc123!'), isNotNull);
      expect(Validators.newPassword(''), isNotNull);
    });

    test('rechaza doce caracteres de una sola clase', () {
      expect(Validators.newPassword('aaaaaaaaaaaa'), isNotNull);
      expect(Validators.newPassword('contrasenaaa'), isNotNull);
    });

    test('acepta una razonable', () {
      expect(Validators.newPassword('Pelicano#84Kx'), isNull);
    });

    test('es más exigente que la del login', () {
      // La del login solo comprueba el mínimo de Supabase: ahí no se está
      // eligiendo una contraseña, se está escribiendo la que ya existe.
      expect(Validators.password('corta1'), isNull);
      expect(Validators.newPassword('corta1'), isNotNull);
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
      for (final bad in const [
        'Admin123admin',
        'MiPassword2026!',
        'Invictor2026!',
        'ClaveSegura99!',
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
