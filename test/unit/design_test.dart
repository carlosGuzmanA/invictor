import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/app/theme.dart';
import 'package:invictor/core/design/palette.dart';

/// La identidad visual se pierde sin hacer ruido.
///
/// Nada se rompe si mañana alguien vuelve a poner el azul de siempre o retira
/// la fuente: la aplicación compila, los tests de lógica pasan y la pantalla
/// sigue funcionando. Solo se ve peor, y eso no lo detecta nada. Estas
/// comprobaciones fijan las decisiones que costaron una sesión entera.
void main() {
  group('la paleta es elegida, no la de la plantilla', () {
    // Los valores exactos de Tailwind. Si la marca es uno de estos, es que
    // nadie eligió el color: es el que venía puesto.
    const tailwind = {
      'blue-600': 0xFF2563EB,
      'blue-500': 0xFF3B82F6,
      'indigo-600': 0xFF4F46E5,
      'violet-600': 0xFF7C3AED,
    };

    test('la marca no es un azul de catálogo', () {
      for (final entry in tailwind.entries) {
        expect(
          Palette.brand.toARGB32(),
          isNot(entry.value),
          reason: 'La marca volvió a ${entry.key}.',
        );
      }
    });

    test('la marca es cálida', () {
      // Terracota: entre el rojo y el naranja. Un tono fuera de ahí ya no es
      // esta aplicación.
      final tono = HSLColor.fromColor(Palette.brand).hue;
      expect(tono, greaterThan(5));
      expect(tono, lessThan(35));
    });

    test('los neutros acompañan a la marca en vez de enfriarla', () {
      // La escala *slate* de Tailwind es azulada: sobre un fondo así el
      // terracota se ve sucio. Estos tiran a arena, que es lo que hace que la
      // pantalla se lea templada sin que nadie sepa decir por qué.
      for (final gris in [Palette.sand900, Palette.sand500, Palette.sand100]) {
        final hsl = HSLColor.fromColor(gris);
        expect(
          hsl.hue,
          inInclusiveRange(10, 50),
          reason: 'Un neutro dejó de ser cálido: $gris',
        );
      }
    });
  });

  group('los colores de aviso no se confunden con la marca', () {
    // Es la comprobación que más importa de todo el archivo. Con una marca
    // naranja-rojiza, el ámbar de «stock bajo» y el rojo de «saldo negativo»
    // caen en el mismo vecindario y dejan de avisar: un número en negativo
    // pasa por decoración. Por eso la alerta se movió de ámbar a dorado.
    double distancia(Color a, Color b) {
      final x = HSLColor.fromColor(a).hue, y = HSLColor.fromColor(b).hue;
      final d = (x - y).abs();
      return d > 180 ? 360 - d : d;
    }

    test('la alerta se distingue de la marca', () {
      expect(distancia(Palette.warning, Palette.brand), greaterThan(15));
    });

    test('el error se distingue de la marca', () {
      // Aquí el tono solo no basta: el rojo y el terracota están cerca en el
      // círculo y lo que de verdad los separa es que el error es mucho más
      // vivo. Un rojo apagado se leería como marca.
      final error = HSLColor.fromColor(Palette.danger);
      final marca = HSLColor.fromColor(Palette.brand);
      expect(
        error.saturation - marca.saturation,
        greaterThan(0.05),
        reason: 'El rojo de error perdió fuerza frente a la marca.',
      );
      expect(error.lightness, greaterThan(marca.lightness));
    });

    test('queda un color frío para lo que solo informa', () {
      // «Jornada abierta» o «hay una versión nueva» no son buenas ni malas
      // noticias. Si también fueran cálidas, todo pesaría lo mismo.
      final tono = HSLColor.fromColor(Palette.info).hue;
      expect(tono, inInclusiveRange(180, 260));
    });
  });

  group('los avisos se leen', () {
    // Un color de aviso que no contrasta con su fondo no avisa. Pasó de
    // verdad: el primer dorado de «stock bajo» se quedaba en 4,0 sobre blanco
    // y en la captura se veía apagado, como si estuviera desactivado. La
    // pantalla se mira en un pasillo con claraboyas y el sol de frente.
    //
    // 4,5 es el mínimo que se pide para texto normal. Aquí importa más que en
    // una web cualquiera: estos colores son los que dicen que algo va mal.
    double luminancia(Color c) {
      double canal(double v) {
        v /= 255;
        return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
      }

      return 0.2126 * canal(c.r * 255) +
          0.7152 * canal(c.g * 255) +
          0.0722 * canal(c.b * 255);
    }

    double contraste(Color a, Color b) {
      final x = luminancia(a), y = luminancia(b);
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
    }

    test('sobre fondo claro', () {
      const fondo = Colors.white;
      final colores = {
        'alerta': Palette.warning,
        'error': Palette.danger,
        'correcto': Palette.positive,
        'información': Palette.info,
        'marca': Palette.brand,
      };

      colores.forEach((nombre, color) {
        expect(
          contraste(color, fondo),
          greaterThanOrEqualTo(4.5),
          reason: 'El color de $nombre no se lee sobre blanco.',
        );
      });
    });

    test('sobre fondo oscuro', () {
      const fondo = Palette.sand950;
      final colores = {
        'alerta': Palette.warningDark,
        'error': Palette.dangerDark,
        'correcto': Palette.positiveDark,
        'información': Palette.infoDark,
        'marca': Palette.brandDark,
      };

      colores.forEach((nombre, color) {
        expect(
          contraste(color, fondo),
          greaterThanOrEqualTo(4.5),
          reason: 'El color de $nombre no se lee sobre el fondo oscuro.',
        );
      });
    });

    test('el texto normal se lee sobre su fondo', () {
      for (final tema in [AppTheme.light, AppTheme.dark]) {
        expect(
          contraste(tema.colorScheme.onSurface, tema.colorScheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        // El texto secundario —unidades, fechas, notas— es el que más fácil se
        // queda corto, porque se elige «suave» sin comprobar nada.
        expect(
          contraste(
              tema.colorScheme.onSurfaceVariant, tema.colorScheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('el texto del botón se lee sobre el botón', () {
      for (final tema in [AppTheme.light, AppTheme.dark]) {
        final c = tema.colorScheme;
        expect(contraste(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
        expect(
          contraste(c.onSecondaryContainer, c.secondaryContainer),
          greaterThanOrEqualTo(4.5),
          reason: 'El botón de «1 salida» no se lee.',
        );
      }
    });
  });

  group('la tipografía va empaquetada', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    test('los cuatro pesos están declarados y existen', () {
      // Si falta el archivo de un peso, la plataforma no se queda corta: lo
      // **finge** engordando el trazo, y eso se ve embarrado en pantallas
      // pequeñas sin que nadie sepa por qué.
      for (final peso in [400, 500, 600, 700]) {
        expect(pubspec, contains('Figtree-$peso.ttf'));
        expect(
          File('assets/fonts/Figtree-$peso.ttf').existsSync(),
          isTrue,
          reason: 'Falta el archivo del peso $peso.',
        );
      }
    });

    test('no se descarga de un servidor de fuentes', () {
      // Una hoja externa añade una petición a otro dominio al arrancar y un
      // salto de texto al llegar, justo en una PWA que se usa con datos
      // móviles dentro de un centro comercial.
      final web = File('web/index.html').readAsStringSync();
      expect(web, isNot(contains('fonts.googleapis.com')));
      expect(web, isNot(contains('fonts.gstatic.com')));
    });

    test('la licencia viaja con la fuente', () {
      expect(File('assets/fonts/OFL.txt').existsSync(), isTrue);
    });

    test('el tema la usa de verdad', () {
      // Declararla sin aplicarla dejaría la fuente en el paquete, sumando peso
      // a la descarga, y la pantalla igual que antes.
      for (final tema in [AppTheme.light, AppTheme.dark]) {
        expect(tema.textTheme.titleLarge?.fontFamily, 'Figtree');
        expect(tema.textTheme.bodyMedium?.fontFamily, 'Figtree');
      }
    });
  });

  group('las cifras no bailan', () {
    test('toda la escala las pide de ancho fijo', () {
      // Un «1» más estrecho que un «8» hace que una cantidad que pasa de 9 a
      // 10 empuje lo que tiene al lado, justo mientras se descuenta y se está
      // mirando. Va en toda la escala porque la lista de estilos «numéricos»
      // siempre se queda corta: el precio de la tarjeta usa `titleLarge`.
      final texto = AppTheme.light.textTheme;
      final estilos = {
        'displaySmall': texto.displaySmall,
        'headlineMedium': texto.headlineMedium,
        'headlineSmall': texto.headlineSmall,
        'titleLarge': texto.titleLarge,
        'titleMedium': texto.titleMedium,
        'titleSmall': texto.titleSmall,
        'bodyLarge': texto.bodyLarge,
        'bodyMedium': texto.bodyMedium,
        'bodySmall': texto.bodySmall,
        'labelLarge': texto.labelLarge,
        'labelMedium': texto.labelMedium,
        'labelSmall': texto.labelSmall,
      };

      estilos.forEach((nombre, estilo) {
        expect(
          estilo?.fontFeatures?.any((f) => f.feature == 'tnum'),
          isTrue,
          reason: '$nombre dejó de pedir cifras de ancho fijo.',
        );
      });
    });

    test('los widgets ya no lo repiten por su cuenta', () {
      // Estaba puesto a mano en trece sitios porque el tema no lo daba. Ahora
      // sí: repetirlo es ruido, y olvidarlo en un widget nuevo sería un
      // desajuste que nadie relacionaría con esto.
      final sueltos = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('app/theme.dart')) continue;
        if (f.readAsStringSync().contains('FontFeature')) {
          sueltos.add(f.path);
        }
      }
      expect(sueltos, isEmpty);
    });
  });

  group('el botón que grita es el raro', () {
    test('crear un producto destaca más que descontar uno', () {
      // Descontar pasa cien veces al día y aparece en cada tarjeta; crear un
      // producto, una vez. Antes los dos salían del mismo rosa derivado de la
      // marca y competían entre sí.
      final tema = AppTheme.light;
      expect(tema.floatingActionButtonTheme.backgroundColor,
          tema.colorScheme.primary);
    });

    test('el relleno suave no es el rosa que salía solo', () {
      // `ColorScheme.fromSeed` deriva del terracota un salmón desvaído que no
      // se parece a la marca. Se fija a mano; se vio en una captura.
      final suave = AppTheme.light.colorScheme.secondaryContainer;
      expect(suave, Palette.brandSoft);
      expect(HSLColor.fromColor(suave).hue, inInclusiveRange(10, 40));
    });

    test('el campo de texto no es del color del fondo', () {
      // Eran idénticos y solo los separaba el borde: en la pantalla de acceso
      // parecían texto suelto con una línea alrededor.
      final tema = AppTheme.light;
      expect(
        tema.inputDecorationTheme.fillColor,
        isNot(tema.scaffoldBackgroundColor),
      );
    });
  });
}
