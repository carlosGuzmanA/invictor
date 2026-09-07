import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';
import 'package:invictor/data/models/inventory_item.dart';
import 'package:invictor/data/models/inventory_movement.dart';
import 'package:invictor/data/models/product.dart';
import 'package:invictor/data/models/stand_catalog_item.dart';

void main() {
  group('Product', () {
    test('acepta `numeric` como String (así lo entrega PostgREST)', () {
      final p = Product.fromMap({
        'id': 'p1',
        'name': 'Oso de peluche',
        'price': '12990.00',
        'min_stock': 3,
        'active': true,
      });
      expect(p.price, 12990.0);
    });

    test('lee `product_id` cuando viene de la vista v_product_stock', () {
      final p = Product.fromMap({
        'product_id': 'p1',
        'name': 'Peluche',
        'price': 9990,
        'min_stock': 5,
        'stock_total': 4,
        'active': true,
      });
      expect(p.id, 'p1');
      expect(p.isLowStock, isTrue); // 4 <= 5
    });

    test('sin stock_total no se puede afirmar que hay stock bajo', () {
      final p = Product.fromMap({
        'id': 'p1',
        'name': 'Peluche',
        'price': 0,
        'min_stock': 5,
        'active': true,
      });
      expect(p.isLowStock, isFalse);
    });
  });

  group('InventoryMovement', () {
    test('toInsertMap no envía signed_quantity (columna generada)', () {
      final m = InventoryMovement(
        id: '',
        productId: 'p1',
        standId: 's1',
        type: MovementType.salida,
        quantity: 2,
        createdAt: DateTime.now(),
      );
      final map = m.toInsertMap();
      expect(map.containsKey('signed_quantity'), isFalse);
      expect(map['quantity'], 2, reason: 'la cantidad se guarda positiva');
      expect(map['type'], 'salida');
    });

    test('effectiveQuantity aplica el signo del tipo', () {
      final salida = InventoryMovement(
        id: 'm1',
        productId: 'p1',
        standId: 's1',
        type: MovementType.salida,
        quantity: 3,
        createdAt: DateTime.now(),
      );
      expect(salida.effectiveQuantity, -3);

      final entrada = InventoryMovement(
        id: 'm2',
        productId: 'p1',
        standId: 's1',
        type: MovementType.entrada,
        quantity: 3,
        createdAt: DateTime.now(),
      );
      expect(entrada.effectiveQuantity, 3);
    });
  });

  group('InventoryItem', () {
    test('toCountUpdateMap no envía `difference` (columna generada)', () {
      const item = InventoryItem(
        id: 'i1',
        inventoryId: 'inv1',
        productId: 'p1',
        systemQty: 5,
        countedQty: 3,
        photoUrl: 'ruta/foto.jpg',
      );
      expect(item.toCountUpdateMap().containsKey('difference'), isFalse);
    });

    test('el ejemplo de la §4.2: sistema 5, físico 3 -> diferencia -2', () {
      final item = InventoryItem.fromMap({
        'id': 'i1',
        'inventory_id': 'inv1',
        'product_id': 'p1',
        'system_qty': 5,
        'counted_qty': 3,
        'difference': -2,
        'photo_url': 'ruta/foto.jpg',
      });
      expect(item.difference, -2);
      expect(item.hasDifference, isTrue);
      expect(item.isReadyToClose, isTrue);
    });

    test('un conteo sin fotografía no puede cerrarse (§19)', () {
      const item = InventoryItem(
        id: 'i1',
        inventoryId: 'inv1',
        productId: 'p1',
        systemQty: 5,
        countedQty: 3,
      );
      expect(item.hasPhoto, isFalse);
      expect(item.isReadyToClose, isFalse);
    });

    test('un producto aún sin contar no bloquea el cierre', () {
      const item = InventoryItem(
        id: 'i1',
        inventoryId: 'inv1',
        productId: 'p1',
        systemQty: 5,
      );
      expect(item.isCounted, isFalse);
      expect(item.isReadyToClose, isTrue);
    });
  });

  group('StandCatalogItem', () {
    Map<String, dynamic> row({int qty = 0, bool inCatalog = true}) => {
          'stand_id': 's1',
          'product_id': 'p1',
          'product_name': 'Peluche Pokémon',
          'quantity': qty,
          'in_catalog': inCatalog,
          'min_stock': 5,
          'price': '9990.00',
        };

    test('un producto asignado sin stock aparece con cantidad 0', () {
      final item = StandCatalogItem.fromMap(row());
      expect(item.quantity, 0);
      expect(item.inCatalog, isTrue);
      expect(item.isLow, isTrue);
      expect(item.isUnexpected, isFalse);
    });

    test('stock sin asignación se marca como inesperado, no se oculta', () {
      final item = StandCatalogItem.fromMap(row(qty: 3, inCatalog: false));
      expect(item.isUnexpected, isTrue,
          reason: 'llegó por traslado: hay que contarlo igual');
    });

    test('cantidad negativa se detecta como anomalía', () {
      final item = StandCatalogItem.fromMap(row(qty: -2));
      expect(item.isNegative, isTrue);
    });
  });
}
