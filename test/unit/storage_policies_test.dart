import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Subir con `upsert: true` resuelve a INSERT si el archivo no existe y a
/// UPDATE si ya existe. Sin policy de UPDATE sobre `storage.objects`, la
/// primera subida funciona y cualquier repetición falla con un 403 confuso
/// ("new row violates row-level security policy").
///
/// Este test ata las dos mitades: si el código usa upsert, el SQL debe
/// conceder UPDATE.
void main() {
  String sql() => Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  test('si se sube con upsert, existe policy de UPDATE en storage.objects', () {
    final storageService =
        File('lib/services/storage_service.dart').readAsStringSync();
    final usesUpsert = storageService.contains('upsert: true');

    if (!usesUpsert) return; // sin upsert no hace falta UPDATE

    expect(
      sql(),
      contains(RegExp(
        r'create policy \w+ on storage\.objects\s+for update',
        caseSensitive: false,
      )),
      reason: 'se sube con upsert pero no hay policy de UPDATE: la segunda '
          'subida a la misma ruta dará 403',
    );
  });

  test('storage cubre las cuatro operaciones', () {
    final all = sql();
    for (final op in ['select', 'insert', 'update', 'delete']) {
      expect(
        all,
        contains(RegExp(
          'create policy \\w+ on storage\\.objects\\s+for $op',
          caseSensitive: false,
        )),
        reason: 'falta la policy de $op sobre storage.objects',
      );
    }
  });

  test('el bucket de fotos es privado', () {
    // Si fuera público, cualquiera con la URL vería la evidencia de inventario.
    expect(
      sql(),
      contains(RegExp(r"values \('inventory', 'inventory', false")),
      reason: 'el bucket inventory debe crearse como privado',
    );
  });

  test('los errores de Storage distinguen permisos de red', () {
    final mapper =
        File('lib/core/errors/app_exception.dart').readAsStringSync();
    expect(mapper, contains("error.statusCode == '403'"),
        reason: 'un 403 no debe reportarse como problema de conexión');
  });
}
