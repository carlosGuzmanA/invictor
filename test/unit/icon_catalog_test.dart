import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/design/product_icons.dart';

/// El catálogo de iconos se reparte entre la base (identificadores de texto) y
/// el cliente (el mapeo a un icono). Si se desincronizan, un producto guardado
/// con "mochila" dibujaría el icono genérico sin dar ningún error.
void main() {
  /// Identificadores de icono que asigna cualquier migración.
  ///
  /// Se acota a las sentencias que tocan `categories`/`products`: buscar
  /// tuplas de tres textos en todo el archivo capturaba también los valores de
  /// `create type ... as enum ('admin', 'encargado', 'vendedor')`.
  Set<String> idsUsedInSql() {
    final ids = <String>{};

    for (final f in Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))) {
      final sql = f.readAsStringSync();

      // `update ... set icon = 'x'`
      ids.addAll(RegExp(r"set icon\s*=\s*'(\w+)'")
          .allMatches(sql)
          .map((m) => m.group(1)!));

      // `insert into ... categories (... icon) values (...), (...);`
      for (final block in RegExp(
        r'insert into public\.categories[^;]*?values([\s\S]*?);',
        caseSensitive: false,
      ).allMatches(sql)) {
        ids.addAll(RegExp(r"'([a-z_]+)'\s*\)")
            .allMatches(block.group(1)!)
            .map((m) => m.group(1)!));
      }
    }
    return ids;
  }

  test('todo identificador usado en SQL lo reconoce el cliente', () {
    final used = idsUsedInSql();
    expect(used, isNotEmpty, reason: 'no se encontró ningún icono en el SQL');

    final unknown = used.where((id) => !ProductIcons.isKnown(id)).toList()
      ..sort();
    expect(unknown, isEmpty,
        reason: 'el SQL asigna iconos que el cliente no conoce: $unknown');
  });

  test('no hay identificadores duplicados', () {
    final ids = ProductIcons.ids;
    expect(ids.length, ids.toSet().length,
        reason: 'un id duplicado hace impredecible qué icono gana');
  });

  test('cada icono tiene etiqueta legible', () {
    for (final option in ProductIcons.all) {
      expect(option.label.trim(), isNotEmpty, reason: option.id);
      expect(option.id, matches(RegExp(r'^[a-z_]+$')),
          reason: 'los ids van en minúsculas sin acentos: ${option.id}');
    }
  });

  test('los grupos cubren todos los iconos', () {
    final grouped =
        ProductIcons.grouped.values.expand((e) => e).map((e) => e.id).toSet();
    expect(grouped, ProductIcons.ids.toSet());
  });

  test('el catálogo cubre lo que se vende de verdad', () {
    // Peluches, mochilas, muñecas, figuras, llaveros, libretas, stickers,
    // camisetas y accesorios de pelo.
    for (final id in [
      'peluche',
      'mochila',
      'muneca',
      'figura',
      'llavero',
      'cuaderno',
      'sticker',
      'ropa',
      'accesorio',
    ]) {
      expect(ProductIcons.isKnown(id), isTrue, reason: 'falta "$id"');
    }
  });

  test('un identificador desconocido cae al genérico', () {
    expect(ProductIcons.resolve('no_existe'), ProductIcons.fallback);
    expect(ProductIcons.resolve(null), ProductIcons.fallback);
    expect(ProductIcons.labelOf('no_existe'), isNull);
  });
}
