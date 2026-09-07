import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';
import 'package:invictor/core/design/product_icons.dart';

/// Deshacer un descuento registra el movimiento contrario, nunca borra (§19).
/// Si el tipo opuesto estuviera mal elegido, "deshacer" movería el stock en la
/// dirección equivocada — el peor fallo posible aquí, porque el trabajador
/// creería haber corregido algo que en realidad empeoró.
void main() {
  final source = File('lib/services/movement_service.dart').readAsStringSync();

  /// Extrae los pares `MovementType.x => MovementType.y` del switch.
  Map<String, String> compensationPairs() {
    final block = RegExp(r'final opposite = switch \(original\.type\) \{([\s\S]*?)\};')
        .firstMatch(source);
    expect(block, isNotNull, reason: 'no se encontró el switch de compensate');

    final pairs = <String, String>{};
    for (final m in RegExp(
      r'MovementType\.(\w+) => MovementType\.(\w+)',
    ).allMatches(block!.group(1)!)) {
      pairs[m.group(1)!] = m.group(2)!;
    }
    return pairs;
  }

  test('cada tipo de movimiento tiene compensación definida', () {
    final pairs = compensationPairs();
    for (final type in MovementType.values) {
      expect(pairs.containsKey(type.name), isTrue,
          reason: 'falta la compensación de ${type.name}');
    }
  });

  test('la compensación siempre tiene el signo contrario', () {
    final byName = {for (final t in MovementType.values) t.name: t};

    compensationPairs().forEach((from, to) {
      final original = byName[from]!;
      final opposite = byName[to]!;
      expect(
        opposite.sign,
        -original.sign,
        reason: 'compensar ${original.wireValue} con ${opposite.wireValue} '
            'movería el stock en la misma dirección',
      );
    });
  });

  test('una salida se compensa con una devolución, no con un ajuste', () {
    // Ambas son operativas, así que un vendedor puede deshacer su propio
    // descuento. Con un ajuste, RLS se lo impediría (migración 0003).
    expect(compensationPairs()['salida'], 'devolucion');
    expect(
      MovementType.operationalTypes.map((t) => t.name),
      containsAll(['salida', 'devolucion']),
    );
  });

  test('deshacer deja rastro, no borra', () {
    expect(source, isNot(contains(RegExp(r'\.delete\(\)'))),
        reason: 'los movimientos son inmutables: nunca se eliminan');
    expect(source, contains('Corrección de un registro anterior'),
        reason: 'la compensación debe quedar identificada en el historial');
  });

  group('iconos de categoría', () {
    test('un identificador desconocido no rompe la pantalla', () {
      expect(ProductIcons.resolve('inventado'), ProductIcons.fallback);
      expect(ProductIcons.resolve(null), ProductIcons.fallback);
      expect(ProductIcons.resolve(''), ProductIcons.fallback);
    });

    test('ignora mayúsculas y espacios', () {
      final base = ProductIcons.resolve('peluche');
      expect(ProductIcons.resolve('  PELUCHE '), base);
      expect(base, isNot(ProductIcons.fallback));
    });

    test('los identificadores del SQL están todos soportados', () {
      final sql = File('supabase/migrations/0007_category_icons.sql')
          .readAsStringSync();

      final used = RegExp(r"set icon = '(\w+)'")
          .allMatches(sql)
          .map((m) => m.group(1)!)
          .toSet();

      expect(used, isNotEmpty);
      for (final id in used) {
        expect(ProductIcons.resolve(id), isNot(ProductIcons.fallback),
            reason: '"$id" se asigna en SQL pero el cliente no lo reconoce');
      }
    });
  });
}
