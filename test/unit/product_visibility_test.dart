import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/utils/validators.dart';

/// `v_stand_catalog` solo muestra productos asignados al puesto o con saldo
/// distinto de cero. Un producto creado sin asignar quedaría guardado pero
/// **invisible en toda la app**: no daría error, simplemente no aparecería.
///
/// Este guard ata las dos mitades: si la vista mantiene ese filtro, el
/// formulario tiene que asignar el producto nuevo a un puesto.
void main() {
  String latestCatalogView() {
    final files = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    String? found;
    for (final f in files) {
      final matches = RegExp(
        r'create (?:or replace )?view public\.v_stand_catalog([\s\S]*?);\s*\n',
        caseSensitive: false,
      ).allMatches(f.readAsStringSync());
      if (matches.isNotEmpty) found = matches.last.group(1);
    }
    expect(found, isNotNull);
    return found!;
  }

  test('la vista filtra por asignación o saldo', () {
    expect(latestCatalogView(), contains('sp.stand_id is not null'));
  });

  test('crear un producto lo asigna a un puesto', () {
    final form =
        File('lib/features/products/presentation/product_form_sheet.dart')
            .readAsStringSync();

    expect(
      form,
      contains('assignProductsToStand'),
      reason: 'sin esto el producto se guarda pero no aparece en ningún sitio',
    );
    expect(
      form,
      contains(RegExp(r'if \(_isNew && widget\.standId != null\)')),
      reason: 'la asignación solo corresponde al crear, no al editar',
    );
  });

  test('la pantalla entrega el puesto activo al formulario', () {
    final tab = File('lib/features/home/presentation/products_tab.dart')
        .readAsStringSync();
    expect(tab, contains('standId: stand.id'));
  });

  // El único campo con la palabra "stock" era el umbral de alerta, así que
  // escribir ahí las unidades que había parecía lo correcto. El producto
  // quedaba en cero y la primera salida avisaba de stock negativo — sin que
  // nada estuviera mal guardado.
  group('existencias iniciales frente a umbral de alerta', () {
    final form =
        File('lib/features/products/presentation/product_form_sheet.dart')
            .readAsStringSync();

    test('hay dónde poner las unidades que ya existen', () {
      expect(form, contains('_initialStockCtrl'));
      expect(form, contains('Unidades que hay ahora'));
    });

    test('el umbral no se anuncia como una cantidad existente', () {
      expect(form, isNot(contains("labelText: 'Stock mínimo'")),
          reason: '"Stock mínimo" es justo lo que se confundió');
      expect(form, contains('No son unidades existentes'));
    });

    test('las existencias iniciales entran como movimiento de entrada', () {
      // Escribir `stand_stock` a mano dejaría el saldo sin rastro en el
      // historial, y RLS no lo permite: el saldo lo actualiza un trigger.
      //
      // Los comentarios se descartan antes de buscar: este archivo explica en
      // prosa por qué NO se escribe `stand_stock`, y esa mención bastaba para
      // dar el guard por bueno sin comprobar nada.
      final code = form
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(code, contains('MovementType.entrada'));
      expect(code, contains('registerMovement'));
      expect(code, isNot(contains('stand_stock')));
    });

    test('un número mal escrito no se guarda como cero en silencio', () {
      expect(Validators.optionalQuantity(''), isNull);
      expect(Validators.optionalQuantity('10'), isNull);
      expect(Validators.optionalQuantity('diez'), isNotNull);
      expect(Validators.optionalQuantity('-1'), isNotNull);
    });
  });
}
