import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
