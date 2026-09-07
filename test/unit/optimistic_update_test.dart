import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';
import 'package:invictor/data/models/stand_catalog_item.dart';
import 'package:invictor/features/movements/presentation/movement_sheet.dart';

/// El stock mostrado se ajusta en local antes de que el servidor confirme.
/// Si el signo o la cantidad del delta fueran incorrectos, el trabajador vería
/// un número equivocado durante el segundo que tarda el refresco — y como
/// después se corrige solo, sería un fallo difícil de reproducir.
void main() {
  group('delta de un movimiento registrado', () {
    test('una salida resta', () {
      const m = RegisteredMovement(type: MovementType.salida, quantity: 3);
      expect(m.delta, -3);
    });

    test('una entrada suma', () {
      const m = RegisteredMovement(type: MovementType.entrada, quantity: 3);
      expect(m.delta, 3);
    });

    test('una devolución suma', () {
      const m = RegisteredMovement(type: MovementType.devolucion, quantity: 2);
      expect(m.delta, 2);
    });

    test('los ajustes respetan su signo', () {
      expect(
        const RegisteredMovement(
                type: MovementType.ajustePositivo, quantity: 5)
            .delta,
        5,
      );
      expect(
        const RegisteredMovement(
                type: MovementType.ajusteNegativo, quantity: 5)
            .delta,
        -5,
      );
    });

    test('el delta coincide con el signo declarado en el enum', () {
      // Si alguien cambia el signo de un tipo, esto lo detecta.
      for (final type in MovementType.values) {
        final m = RegisteredMovement(type: type, quantity: 7);
        expect(m.delta, 7 * type.sign, reason: type.wireValue);
      }
    });
  });

  group('copyWith del catálogo', () {
    const item = StandCatalogItem(
      standId: 's1',
      productId: 'p1',
      productName: 'Peluche',
      quantity: 10,
      inCatalog: true,
      minStock: 3,
      sku: 'PEL-001',
    );

    test('cambia solo la cantidad', () {
      final updated = item.copyWith(quantity: 7);
      expect(updated.quantity, 7);
      expect(updated.productId, item.productId);
      expect(updated.productName, item.productName);
      expect(updated.sku, item.sku);
      expect(updated.minStock, item.minStock);
      expect(updated.inCatalog, item.inCatalog);
    });

    test('recalcula el estado de alerta con la cantidad nueva', () {
      expect(item.isLow, isFalse); // 10 > 3
      expect(item.copyWith(quantity: 3).isLow, isTrue);
      expect(item.copyWith(quantity: -1).isNegative, isTrue);
    });

    test('sin argumentos conserva el valor', () {
      expect(item.copyWith().quantity, 10);
    });
  });
}
