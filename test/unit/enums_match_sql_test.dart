import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';

/// Guarda contra la desincronización silenciosa entre los enums de Dart y los
/// tipos de PostgreSQL. Si alguien agrega un valor en el SQL y olvida el Dart
/// (o al revés), este test falla en vez de romperse en producción con un
/// `fromWire` cayendo al valor por defecto.
void main() {
  final schema = File('supabase/migrations/0001_schema.sql').readAsStringSync();

  /// Todas las migraciones juntas.
  ///
  /// Los tipos nuevos no nacen en `0001`: `shipment_status` llegó en `0013`.
  /// Buscar solo en el esquema inicial dejaba fuera de vigilancia justo a los
  /// enums más recientes, que son los que más se mueven.
  final allMigrations = (Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      .map((f) => f.readAsStringSync())
      .join('\n');

  /// Extrae los literales de `create type public.<name> as enum (...)`.
  ///
  /// El cierre se ancla a `);` y no a un simple `)`, porque los comentarios
  /// del SQL contienen paréntesis — `-- (+) ingreso de mercadería`.
  Set<String> sqlEnumValues(String typeName) {
    final match = RegExp(
      "create type public\\.$typeName as enum\\s*\\(([\\s\\S]*?)\\);",
      caseSensitive: false,
    ).firstMatch(allMigrations);

    expect(match, isNotNull, reason: 'No se encontró el tipo $typeName en el SQL');

    return RegExp("'([a-z_]+)'")
        .allMatches(match!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
  }

  test('user_role coincide con UserRole', () {
    expect(
      UserRole.values.map((e) => e.wireValue).toSet(),
      sqlEnumValues('user_role'),
    );
  });

  test('stand_type coincide con StandType', () {
    expect(
      StandType.values.map((e) => e.wireValue).toSet(),
      sqlEnumValues('stand_type'),
    );
  });

  test('movement_type coincide con MovementType', () {
    expect(
      MovementType.values.map((e) => e.wireValue).toSet(),
      sqlEnumValues('movement_type'),
    );
  });

  test('inventory_status coincide con InventoryStatus', () {
    expect(
      InventoryStatus.values.map((e) => e.wireValue).toSet(),
      sqlEnumValues('inventory_status'),
    );
  });

  test('el signo de cada movimiento coincide con signed_quantity del SQL', () {
    // La columna generada lista los tipos que suman; el resto resta.
    final match = RegExp(
      r'case when type in \(([^)]*)\)',
      caseSensitive: false,
    ).firstMatch(schema);
    expect(match, isNotNull, reason: 'No se encontró signed_quantity en el SQL');

    final positiveInSql = RegExp("'([a-z_]+)'")
        .allMatches(match!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    final positiveInDart = MovementType.values
        .where((t) => t.sign > 0)
        .map((t) => t.wireValue)
        .toSet();

    expect(positiveInDart, positiveInSql);
  });

}
