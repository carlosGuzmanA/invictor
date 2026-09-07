import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/data/models/sales.dart';

/// Los errores en ventas no dan excepciones: dan números plausibles y falsos.
/// Un administrador tomaría decisiones de compra sobre ellos sin sospechar.
void main() {
  final priceSql =
      File('supabase/migrations/0011_movement_price.sql').readAsStringSync();
  final salesSql =
      File('supabase/migrations/0012_sales_views.sql').readAsStringSync();

  group('precio histórico', () {
    test('el movimiento guarda su propio precio', () {
      expect(priceSql, contains('add column if not exists unit_price'));
    });

    test('lo copia el servidor, no el cliente', () {
      // Si lo enviara el cliente, cualquiera podría registrar una salida con
      // un precio inventado y falsear los ingresos.
      expect(priceSql, contains('before insert on public.inventory_movements'));
      expect(priceSql, contains('security definer'));
    });

    test('las ventas se valorizan con unit_price, no con products.price', () {
      // Leer products.price reescribiría el pasado al cambiar un precio.
      expect(salesSql, contains('m.unit_price'));
      final salesView = RegExp(
        r'create or replace view public\.v_sales_movements([\s\S]*?);\s*\n',
      ).firstMatch(salesSql);
      expect(salesView!.group(1), isNot(contains('p.price')),
          reason: 'valorizar con el precio actual falsearía los meses pasados');
    });
  });

  group('qué cuenta como venta', () {
    test('solo salidas y devoluciones', () {
      final view = RegExp(
        r'create or replace view public\.v_sales_movements([\s\S]*?);\s*\n',
      ).firstMatch(salesSql);
      expect(view!.group(1),
          contains("where m.type in ('salida', 'devolucion')"));
    });

    test('los ajustes quedan fuera', () {
      // Un ajuste_negativo es merma o descuadre: sumarlo inflaría los
      // ingresos con mercadería que nadie pagó.
      final view = RegExp(
        r'create or replace view public\.v_sales_movements([\s\S]*?);\s*\n',
      ).firstMatch(salesSql);
      expect(view!.group(1), isNot(contains('ajuste')));
    });

    test('una devolución resta unidades e importe', () {
      final view = RegExp(
        r'create or replace view public\.v_sales_movements([\s\S]*?);\s*\n',
      ).firstMatch(salesSql);
      final body = view!.group(1)!;
      expect(body, contains("when m.type = 'devolucion' then -m.quantity"));
      expect(body, contains("when m.type = 'devolucion' then -1"));
    });

    test('el ranking incluye productos con cero ventas', () {
      // Sin el left join desde products, el "menos vendido" sería el peor de
      // los que se vendieron, no el que lleva semanas parado.
      final fn = RegExp(
        r'create or replace function public\.product_sales([\s\S]*?)\$\$;',
      ).firstMatch(salesSql);
      expect(fn!.group(1), contains('from public.products p'));
      expect(fn.group(1), contains('left join public.v_sales_movements'));
    });

    test('el día se agrupa en hora de Chile', () {
      expect(salesSql, contains('America/Santiago'));
      expect(salesSql, contains('public.local_day_start'));
    });
  });

  group('comparación de períodos', () {
    SalesSummary s({
      int units = 0,
      double amount = 0,
      int prevUnits = 0,
      double prevAmount = 0,
      int products = 0,
    }) =>
        SalesSummary(
          units: units,
          amount: amount,
          products: products,
          prevUnits: prevUnits,
          prevAmount: prevAmount,
        );

    test('calcula el crecimiento', () {
      final summary = s(amount: 118, prevAmount: 100);
      expect(summary.amountChange, closeTo(0.18, 0.001));
      expect(summary.isGrowing, isTrue);
    });

    test('calcula la caída', () {
      final summary = s(amount: 80, prevAmount: 100);
      expect(summary.amountChange, closeTo(-0.20, 0.001));
      expect(summary.isGrowing, isFalse);
    });

    test('sin período anterior no inventa un porcentaje', () {
      // Un crecimiento "infinito" desde cero no informa de nada, y mostrar
      // "+100 %" sería directamente falso.
      final summary = s(amount: 500, prevAmount: 0);
      expect(summary.amountChange, isNull);
      expect(summary.unitsChange, isNull);
    });

    test('el precio medio no divide por cero', () {
      expect(s().averageTicket, 0);
      expect(s(units: 4, amount: 4000).averageTicket, 1000);
    });
  });

  group('productos parados', () {
    ProductSales p({
      int units = 0,
      int stock = 0,
      DateTime? lastSale,
      double amount = 0,
    }) =>
        ProductSales(
          productId: 'p1',
          productName: 'Perfume',
          units: units,
          amount: amount,
          stockNow: stock,
          lastSaleAt: lastSale,
        );

    test('sin ventas y con stock está parado', () {
      expect(p(units: 0, stock: 8).isStagnant, isTrue);
    });

    test('sin ventas y sin stock no está parado', () {
      // No hay capital inmovilizado: no urge nada.
      expect(p(units: 0, stock: 0).isStagnant, isFalse);
    });

    test('con ventas no está parado aunque quede stock', () {
      expect(p(units: 3, stock: 8).isStagnant, isFalse);
    });

    test('distingue el que nunca se vendió', () {
      expect(p().neverSold, isTrue);
      expect(p(lastSale: DateTime.now()).neverSold, isFalse);
    });
  });

  test('numeric de PostgREST puede llegar como texto', () {
    final summary = SalesSummary.fromMap({
      'units': 4,
      'amount': '51960.00',
      'products': 2,
      'prev_units': 3,
      'prev_amount': '38970.00',
    });
    expect(summary.amount, 51960.0);
    expect(summary.prevAmount, 38970.0);
  });
}
