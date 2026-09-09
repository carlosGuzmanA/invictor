import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/data/models/product.dart';

/// La mercadería llega al puesto y hay que registrarla, sepa o no el vendedor
/// cuánto vale. Si crear productos fuera solo cosa de staff, lo que llegó se
/// quedaría fuera del sistema hasta que alguien contestara el teléfono.
///
/// El esquema de encomiendas (`0013`) se retiró de la interfaz por no usarse,
/// pero dos piezas suyas son la base de este flujo y siguen en pie: los
/// permisos que dejan a un vendedor crear productos, y `price_confirmed`.
void main() {
  final shipmentsMigration =
      File('supabase/migrations/0013_shipments.sql').readAsStringSync();
  final arrivalsMigration =
      File('supabase/migrations/0014_vendor_registers_arrivals.sql')
          .readAsStringSync();

  String code(String path) => File(path)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('un vendedor registra lo que llegó', () {
    test('puede crear productos, pero solo sin precio confirmado', () {
      expect(shipmentsMigration, contains('create policy products_insert'));
      expect(shipmentsMigration, contains('price_confirmed = false'));
    });

    test('un producto pendiente sigue editable, para adjuntar la foto', () {
      // La foto se sube después de crear la fila, porque la ruta en Storage se
      // nombra con el id. Sin update, no habría forma de adjuntarla.
      expect(shipmentsMigration, contains('create policy products_update'));
    });

    test('borrar productos sigue siendo del administrador', () {
      final policy = RegExp(r'create policy products_delete[\s\S]*?;')
          .firstMatch(shipmentsMigration);
      expect(policy, isNotNull);
      expect(policy!.group(0), contains('is_admin()'));
    });

    test('puede añadir productos al catálogo de su puesto', () {
      // Sin esto el producto se creaba y quedaba invisible: `v_stand_catalog`
      // solo muestra lo asignado al puesto o lo que tenga saldo. Sin error y
      // sin efecto, que es el peor resultado posible.
      expect(arrivalsMigration, contains('create policy stand_products_insert'));
      expect(arrivalsMigration, contains('public.has_stand_access(stand_id)'));
    });

    test('quitar del catálogo sigue siendo de staff', () {
      final policy = RegExp(r'create policy stand_products_delete[\s\S]*?;')
          .firstMatch(arrivalsMigration);
      expect(policy, isNotNull);
      expect(policy!.group(0), contains('is_staff()'));
    });

    test('el update existe, porque asignar es un upsert', () {
      // Si el producto ya estaba en el catálogo desactivado, la operación lo
      // reactiva; sin permiso de update fallaría por el índice único.
      expect(arrivalsMigration, contains('create policy stand_products_update'));
    });

    test('el botón de crear producto no es solo para staff', () {
      final tab = code('lib/features/home/presentation/products_tab.dart');
      expect(tab, contains('canOperate && activeStand.value != null'));
      expect(tab, isNot(contains('isStaff && activeStand.value != null')),
          reason: 'un vendedor tiene que poder registrar lo que le llegó');
    });
  });

  group('precio por confirmar', () {
    test('un producto nace con el precio confirmado salvo que se diga', () {
      // El default protege a los que ya existían: no deben aparecer como
      // pendientes de golpe al aplicar la migración.
      const p = Product(
        id: 'p1',
        name: 'Taza',
        price: 5990,
        minStock: 0,
        active: true,
      );
      expect(p.priceConfirmed, isTrue);
      expect(p.needsPrice, isFalse);

      expect(shipmentsMigration,
          contains('add column if not exists price_confirmed'));
      expect(shipmentsMigration, contains('not null default true'));
    });

    test('sin precio confirmado, pide que se complete', () {
      const p = Product(
        id: 'p2',
        name: 'Algo que llegó',
        price: 0,
        minStock: 0,
        active: true,
        priceConfirmed: false,
      );
      expect(p.needsPrice, isTrue);
    });

    test('un precio en blanco no se confirma', () {
      // Un 0 no distingue "gratis" de "todavía no lo sé".
      final form =
          code('lib/features/products/presentation/product_form_sheet.dart');
      expect(form, contains('hasPrice'));
      expect(form, contains('priceConfirmed: hasPrice'));
    });

    test('ponerle precio a un pendiente lo cierra', () {
      // Sin esto haría falta un paso aparte para confirmarlo, y nadie lo daría.
      final form =
          code('lib/features/products/presentation/product_form_sheet.dart');
      expect(
        RegExp(r'priceConfirmed: hasPrice').allMatches(form).length,
        2,
        reason: 'al crear y al editar',
      );
    });

    test('el aviso lleva a completarlos, no solo informa', () {
      // Avisar sin dar el camino deja el problema a la vista y a medias.
      final tab = code('lib/features/home/presentation/products_tab.dart');
      expect(tab, contains('_PendingPriceBanner'));
      expect(tab, contains('fetchPendingPriceProducts'));
      expect(tab, contains('ProductFormSheet.show(context, product: product)'));
    });
  });
}
