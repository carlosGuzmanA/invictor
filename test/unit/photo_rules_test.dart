import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/errors/app_exception.dart';
import 'package:invictor/data/models/inventory_item.dart';
import 'package:invictor/services/photo_service.dart';

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

  // Un fallo de cámara ocurre en el móvil de un trabajador, sin consola del
  // navegador a mano. Si el mensaje no dice qué falló de verdad, el
  // diagnóstico se hace a ciegas.
  group('diagnóstico de la captura', () {
    test('sin causa no añade ruido a la interfaz', () {
      expect(technicalDetail(const AppException('algo falló')), isNull);
    });

    test('incluye el tipo del error y la etapa', () {
      final detail = technicalDetail(
        AppException('no se pudo', code: PhotoStage.pick.code,
            cause: StateError('sin permiso')),
      );

      expect(detail, contains('StateError'));
      expect(detail, contains('sin permiso'));
      expect(detail, contains(PhotoStage.pick.code));
    });

    test('recorta un error larguísimo en vez de romper el diseño', () {
      final detail = technicalDetail(
        AppException('no se pudo', cause: StateError('x' * 5000)),
      );

      expect(detail!.length, lessThan(300));
      expect(detail, endsWith('…'));
    });

    test('cada etapa tiene un código distinto', () {
      final codes = PhotoStage.values.map((s) => s.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('la captura no culpa a la cámara de cualquier fallo', () {
      final source = File('lib/services/photo_service.dart').readAsStringSync();

      // Antes un único try/catch envolvía abrir la cámara, leer los bytes y
      // comprimir, y los tres fallos salían como "revisa los permisos".
      for (final stage in PhotoStage.values) {
        expect(source, contains(stage.code),
            reason: 'la etapa ${stage.name} debe distinguirse en el error');
      }

      final readFailure = source.indexOf('no se pudo leer del dispositivo');
      expect(readFailure, greaterThan(-1),
          reason: 'un fallo al leer no es un problema de permisos');
    });
  });
}
