import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/data/models/inventory_item.dart';

/// La regla de fotografías vive en dos sitios que deben coincidir: la interfaz
/// (que decide cuándo exigirla) y `finalize_inventory()` (que la aplica de
/// verdad). Si divergen, o se bloquea un cierre legítimo o se cierra una
/// jornada sin la evidencia del descuadre.
void main() {
  final migration =
      File('supabase/migrations/0004_photo_rules.sql').readAsStringSync();

  InventoryItem item({
    required int system,
    int? counted,
    String? photo,
  }) =>
      InventoryItem(
        id: 'i1',
        inventoryId: 'inv1',
        productId: 'p1',
        systemQty: system,
        countedQty: counted,
        difference: counted == null ? null : counted - system,
        photoUrl: photo,
      );

  group('cuándo hace falta la foto', () {
    test('sin diferencia no se exige', () {
      final i = item(system: 5, counted: 5);
      expect(i.hasDifference, isFalse);
      expect(i.hasPhoto, isFalse);
    });

    test('con diferencia y sin foto, queda pendiente', () {
      final i = item(system: 5, counted: 3);
      expect(i.hasDifference, isTrue);
      expect(i.hasPhoto, isFalse);
    });

    test('con diferencia y con foto, resuelto', () {
      final i = item(system: 5, counted: 3, photo: 'ruta/foto.jpg');
      expect(i.hasDifference, isTrue);
      expect(i.hasPhoto, isTrue);
    });

    test('sin contar no cuenta como diferencia', () {
      final i = item(system: 5);
      expect(i.isCounted, isFalse);
      expect(i.hasDifference, isFalse);
    });
  });

  group('la migración aplica la regla acordada', () {
    test('exige foto SOLO donde hay diferencia', () {
      final check = RegExp(
        r'select count\(\*\) into v_missing([\s\S]*?)if v_missing',
      ).firstMatch(migration);
      expect(check, isNotNull);

      final body = check!.group(1)!;
      expect(body, contains('difference <> 0'),
          reason: 'sin esto exigiría foto en todos los productos contados');
      expect(body, contains('photo_url is null'));
    });

    test('exige la foto general de vitrina para cerrar', () {
      expect(migration, contains('overview_photo_url'));
      expect(
        migration,
        contains(RegExp(r'if v_overview is null', caseSensitive: false)),
        reason: 'la foto de vitrina debe bloquear el cierre',
      );
    });

    test('rechaza cerrar una jornada sin ningún conteo', () {
      expect(migration, contains('v_counted = 0'),
          reason: 'cerrar sin contar dejaría el puesto bloqueado');
    });

    test('sigue comprobando el acceso al puesto', () {
      // finalize_inventory es SECURITY DEFINER: se salta RLS por diseño.
      expect(migration, contains('has_stand_access'));
    });
  });
}
