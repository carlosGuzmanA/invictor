import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/size_templates.dart';
import 'package:invictor/data/models/stand_catalog_item.dart';
import 'package:invictor/features/home/presentation/variant_sheet.dart';
import 'package:invictor/features/products/presentation/size_picker.dart';

/// Una polera no es un producto: son trece. Cada talla tiene su stock y su
/// precio, y por eso cada talla **es** un producto en este sistema. Lo que
/// faltaba no era una entidad nueva sino saber cuáles son del mismo modelo.
void main() {
  StandCatalogItem item({
    required String id,
    String? parent,
    String? size,
    int order = 0,
    int qty = 0,
    double price = 0,
    int min = 0,
  }) =>
      StandCatalogItem(
        standId: 's1',
        productId: id,
        productName: parent == null ? id : 'Polera $size',
        quantity: qty,
        inCatalog: true,
        price: price,
        minStock: min,
        parentId: parent,
        variantLabel: size,
        variantOrder: order,
        parentName: parent == null ? null : 'Polera Mickey',
      );

  group('agrupar el catálogo', () {
    test('las tallas de un modelo caen en un solo grupo', () {
      // Sin esto, diez modelos llenan la pantalla con ciento treinta
      // tarjetas y encontrar una es imposible.
      final groups = groupCatalog([
        item(id: 'a', parent: 'm1', size: 'S', order: 20, qty: 3),
        item(id: 'b', parent: 'm1', size: 'M', order: 30, qty: 5),
        item(id: 'c'),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.items, hasLength(2));
      expect(groups.first.name, 'Polera Mickey');
      expect(groups.last.hasVariants, isFalse);
    });

    test('el total del modelo suma sus tallas', () {
      final groups = groupCatalog([
        item(id: 'a', parent: 'm1', size: 'S', qty: 3),
        item(id: 'b', parent: 'm1', size: 'M', qty: 5),
      ]);
      expect(groups.single.quantity, 8);
    });

    test('las tallas salen en su orden, no en el alfabético', () {
      // Alfabéticamente serían L, M, S, XL — que no es como nadie las busca.
      final groups = groupCatalog([
        item(id: 'd', parent: 'm1', size: 'XL', order: 50),
        item(id: 'a', parent: 'm1', size: 'S', order: 20),
        item(id: 'c', parent: 'm1', size: 'L', order: 40),
        item(id: 'b', parent: 'm1', size: 'M', order: 30),
      ]);

      expect(
        groups.single.items.map((i) => i.variantLabel).toList(),
        ['S', 'M', 'L', 'XL'],
      );
    });

    test('un producto suelto es un grupo de uno, no un modelo', () {
      final groups = groupCatalog([item(id: 'solo', qty: 4)]);
      expect(groups.single.hasVariants, isFalse);
      expect(groups.single.quantity, 4);
    });

    test('el orden de los grupos respeta el de entrada', () {
      // La lista llega ordenada por nombre; reordenar aquí haría que buscar
      // o filtrar barajara la pantalla entera.
      final groups = groupCatalog([
        item(id: 'zeta'),
        item(id: 'alfa'),
      ]);
      expect(groups.map((g) => g.id).toList(), ['zeta', 'alfa']);
    });

    test('una talla en negativo marca todo el modelo', () {
      final groups = groupCatalog([
        item(id: 'a', parent: 'm1', size: 'S', qty: 5),
        item(id: 'b', parent: 'm1', size: 'M', qty: -2),
      ]);
      expect(groups.single.hasNegative, isTrue);
      expect(groups.single.alerts, 1);
    });

    test('el rango de precios distingue niño de adulto', () {
      final groups = groupCatalog([
        item(id: 'a', parent: 'm1', size: '8', order: 10, price: 5990),
        item(id: 'b', parent: 'm1', size: 'S', order: 20, price: 7990),
      ]);
      expect(groups.single.priceRange, (5990.0, 7990.0));
    });
  });

  group('elegir tallas al crear', () {
    test('las plantillas traen el orden, no el alfabeto', () {
      final choices = toSizeChoices({
        'XL': PriceBand.adults,
        'S': PriceBand.adults,
        '8': PriceBand.kids,
      });

      expect(choices.map((c) => c.label).toList(), ['8', 'S', 'XL']);
    });

    test('una talla inventada va al final, no se pierde', () {
      // «Única» o «XXXL» no están en ninguna plantilla; sin esto habría que
      // crear el producto y editarlo después.
      final choices = toSizeChoices({
        'Única': PriceBand.adults,
        'M': PriceBand.adults,
      });

      expect(choices.last.label, 'Única');
      expect(choices.first.label, 'M');
    });

    test('cada talla lleva la banda con la que se creó', () {
      final choices = toSizeChoices({
        '8': PriceBand.kids,
        'XL': PriceBand.adults,
      });

      expect(
        choices.firstWhere((c) => c.label == '8').band,
        PriceBand.kids,
      );
      expect(
        choices.firstWhere((c) => c.label == 'XL').band,
        PriceBand.adults,
      );
    });

    test('las tallas de niño llegan hasta la 16, de dos en dos', () {
      // No existe la talla 3.
      expect(SizeTemplate.kids.sizes, ['2', '4', '6', '8', '10', '12', '14', '16']);
      expect(SizeTemplate.adults.sizes, ['S', 'M', 'L', 'XL', 'XXL']);
    });
  });

  group('el modelo padre no se vende', () {
    final migration =
        File('supabase/migrations/0018_product_variants.sql')
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('--'))
            .join('\n');

    test('la vista lo excluye del catálogo del puesto', () {
      // Si apareciera como una línea más, alguien descontaría de un producto
      // que no tiene tallas y el stock dejaría de cuadrar.
      expect(migration, contains('not exists'));
      expect(migration, contains('ch.parent_id = p.id'));
    });

    test('una talla no puede colgar de otra talla', () {
      // Al agrupar quedarían productos bajo un padre que a su vez está
      // agrupado: no aparecerían por ninguna parte.
      expect(migration, contains('check_variant_depth'));
      expect(migration, contains('Una talla no puede colgar de otra talla'));
    });

    test('no se repite una talla dentro del mismo modelo', () {
      // Serían dos sitios donde registrar lo mismo, y el stock se repartiría
      // entre ambos sin que nadie lo note.
      expect(migration, contains('uq_products_variant'));
    });

    test('el stock y los movimientos no se tocan', () {
      // El motivo de hacerlo así: `product_id` aparece 79 veces en el
      // esquema y cuatro tablas dependen de `products`.
      expect(migration, isNot(contains('alter table public.stand_stock')));
      expect(migration,
          isNot(contains('alter table public.inventory_movements')));
      expect(migration, isNot(contains('variant_id')));
    });
  });

  group('descontar exige decir la talla', () {
    final tab = File('lib/features/home/presentation/products_tab.dart')
        .readAsStringSync();
    final sheet = File('lib/features/home/presentation/variant_sheet.dart')
        .readAsStringSync();

    test('la tarjeta del modelo no descuenta de un toque', () {
      // Elegir una talla por defecto sería equivocarse la mitad de las veces
      // y dejar el stock mal sin que nadie se entere.
      final card = RegExp(r'class _GroupCard[\s\S]*?\n\}')
          .firstMatch(tab);
      expect(card, isNotNull);
      expect(card!.group(0), isNot(contains('onQuickExit')));
    });

    test('la hoja de tallas se cierra antes de descontar', () {
      // El aviso de deshacer sale abajo; con la hoja abierta quedaría tapado
      // justo cuando hay unos segundos para pulsarlo.
      expect(tab, contains('Navigator.of(context).pop();\n        _quickExit'));
    });

    test('cada talla tiene su propio botón', () {
      expect(sheet, contains("Text('−1')"));
      expect(sheet, contains('onExit: () => onExit(group.items[i])'));
    });

    test('no se descuenta de una talla sin stock', () {
      // El botón se apaga: descontar de cero dejaría el saldo en negativo
      // sin que nadie lo haya pedido.
      expect(sheet, contains('item.quantity <= 0'));
    });

    test('la fila no usa ListTile para dos botones', () {
      // El `trailing` de un ListTile no está pensado para eso: en un móvil
      // estrecho desbordaba por la derecha y se llevaba el diseño por
      // delante.
      final row = RegExp(r'class _VariantRow[\s\S]*').firstMatch(sheet);
      expect(row, isNotNull);
      expect(row!.group(0), isNot(contains('ListTile')));
      expect(row.group(0), contains('Expanded('));
    });

    test('la hoja no se come la pantalla', () {
      // Con trece tallas ocupaba todo y tapaba el producto que se mira.
      expect(sheet, contains('maxHeight'));
    });

    test('los textos variables se recortan en vez de desbordar', () {
      final tab = File('lib/features/home/presentation/products_tab.dart')
          .readAsStringSync();
      final card = RegExp(r'class _GroupCard[\s\S]*?\n\}').firstMatch(tab);
      expect(card, isNotNull);
      // Nombre, total y rango de precios crecen con el tamaño de fuente del
      // sistema, y la tarjeta tiene alto fijo.
      expect(
        RegExp('TextOverflow.ellipsis').allMatches(card!.group(0)!).length,
        greaterThanOrEqualTo(3),
      );
    });
  });
}
