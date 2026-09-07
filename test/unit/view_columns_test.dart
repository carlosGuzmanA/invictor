import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Un modelo que lee `map['x']` de una vista que no expone `x` recibe null en
/// silencio. No hay error, no falla ningún test de modelo, y el síntoma aparece
/// lejos de la causa: un botón que se queda en rojo, un dato que "no se guarda"
/// cuando en realidad sí está en la tabla.
///
/// Este test compara lo que cada modelo lee contra lo que su vista devuelve.
void main() {
  /// Última definición de la vista, buscando en todas las migraciones para
  /// respetar los `create or replace` posteriores.
  String viewDefinition(String viewName) {
    final files = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    String? found;
    for (final f in files) {
      // Acepta `create view` y `create or replace view`: una vista que cambia
      // el orden de sus columnas obliga a drop + create (error 42P16).
      final matches = RegExp(
        'create (?:or replace )?view public\\.$viewName([\\s\\S]*?);\\s*\n',
        caseSensitive: false,
      ).allMatches(f.readAsStringSync());
      if (matches.isNotEmpty) found = matches.last.group(1);
    }
    expect(found, isNotNull, reason: 'no se encontró la vista $viewName');
    return found!;
  }

  /// Claves que el modelo lee de un mapa.
  Set<String> modelKeys(String path) => RegExp(r"map\['([a-z_]+)'\]")
      .allMatches(File(path).readAsStringSync())
      .map((m) => m.group(1)!)
      .toSet();

  void checkModelAgainstView({
    required String model,
    required String view,
    /// Claves que llegan de un join anidado al leer desde la tabla, no de la
    /// vista (p. ej. `products(name)`), o alias que la vista renombra.
    Set<String> fromNestedJoins = const {},
  }) {
    final definition = viewDefinition(view);
    final missing = modelKeys(model)
        .difference(fromNestedJoins)
        .where((k) => !definition.contains(k))
        .toList()
      ..sort();

    expect(
      missing,
      isEmpty,
      reason: '$model lee campos que $view no expone: $missing. '
          'Llegarían como null sin dar error.',
    );
  }

  test('Inventory ↔ v_inventory_summary', () {
    checkModelAgainstView(
      model: 'lib/data/models/inventory.dart',
      view: 'v_inventory_summary',
      // Presentes solo al leer desde la tabla `inventories` con joins.
      fromNestedJoins: {'stands', 'profiles'},
    );
  });

  test('StandCatalogItem ↔ v_stand_catalog', () {
    checkModelAgainstView(
      model: 'lib/data/models/stand_catalog_item.dart',
      view: 'v_stand_catalog',
    );
  });

  test('StandStock ↔ v_stand_stock', () {
    checkModelAgainstView(
      model: 'lib/data/models/stand_stock.dart',
      view: 'v_stand_stock',
    );
  });

  test('la vista de inventarios expone la foto de vitrina', () {
    // Regresión concreta: sin esta columna el cierre de jornada queda
    // bloqueado para siempre aunque la foto esté subida.
    expect(
      viewDefinition('v_inventory_summary'),
      contains('overview_photo_url'),
      reason: 'sin esto el botón de cerrar jornada nunca se habilita',
    );
  });
}
