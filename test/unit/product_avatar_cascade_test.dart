import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/design/product_icons.dart';
import 'package:invictor/data/models/stand_catalog_item.dart';
import 'package:invictor/shared/widgets/product_avatar.dart';

/// La imagen del producto se resuelve en cascada: foto propia, luego icono de
/// la categoría, luego genérico. Si la cascada se rompiera en el primer nivel,
/// las tarjetas mostrarían iconos genéricos aunque hubiera fotos subidas — y
/// nadie lo notaría como error, solo como "no se ven las fotos".
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('cascada de imagen', () {
    testWidgets('sin foto ni categoría usa el icono genérico',
        (tester) async {
      await tester.pumpWidget(wrap(const ProductAvatar()));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, ProductIcons.fallback);
    });

    testWidgets('sin foto usa el icono de su categoría', (tester) async {
      await tester.pumpWidget(wrap(
        const ProductAvatar(categoryIcon: 'peluche'),
      ));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, ProductIcons.resolve('peluche'));
      expect(icon.icon, isNot(ProductIcons.fallback));
    });

    testWidgets('con foto no dibuja icono', (tester) async {
      await tester.pumpWidget(wrap(const ProductAvatar(
        imageUrl: 'https://example.test/p.jpg',
        categoryIcon: 'peluche',
      )));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('una url vacía cuenta como sin foto', (tester) async {
      await tester.pumpWidget(wrap(
        const ProductAvatar(imageUrl: '   ', categoryIcon: 'llavero'),
      ));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, ProductIcons.resolve('llavero'));
    });
  });

  group('el modelo transporta ambos niveles', () {
    test('lee image_url y category_icon de la vista', () {
      final item = StandCatalogItem.fromMap({
        'stand_id': 's1',
        'product_id': 'p1',
        'product_name': 'Oso',
        'quantity': 4,
        'in_catalog': true,
        'category_icon': 'peluche',
        'image_url': 'https://example.test/oso.jpg',
      });
      expect(item.categoryIcon, 'peluche');
      expect(item.imageUrl, 'https://example.test/oso.jpg');
    });

    test('copyWith conserva imagen e icono', () {
      const item = StandCatalogItem(
        standId: 's1',
        productId: 'p1',
        productName: 'Oso',
        quantity: 4,
        inCatalog: true,
        categoryIcon: 'peluche',
        imageUrl: 'https://example.test/oso.jpg',
      );
      final updated = item.copyWith(quantity: 3);
      expect(updated.categoryIcon, 'peluche');
      expect(updated.imageUrl, 'https://example.test/oso.jpg');
    });
  });

  test('la vista expone las dos columnas de la cascada', () {
    final sql = File('supabase/migrations/0008_product_photos.sql')
        .readAsStringSync();
    expect(sql, contains('category_icon'));
    expect(sql, contains('p.image_url'));
  });

  test('el bucket de catálogo es público y el de evidencia no', () {
    final products = File('supabase/migrations/0008_product_photos.sql')
        .readAsStringSync();
    final inventory =
        File('supabase/migrations/0005_storage_update_policy.sql')
            .readAsStringSync();

    // Catálogo público: se sirve por URL directa y el navegador lo cachea.
    expect(products, contains(RegExp(r"'products', 'products', true")));
    // Evidencia privada: son fotos de auditoría de conteos.
    expect(inventory, contains(RegExp(r"'inventory', 'inventory', false")));
  });
}
