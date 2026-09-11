import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../data/models/stand_catalog_item.dart';

/// Un modelo con sus tallas, tal como se pinta en la pantalla del puesto.
///
/// Existe porque un producto con tallas son varias filas del catálogo que
/// hablan de lo mismo: sin agrupar, diez modelos de polera llenan la pantalla
/// con ciento treinta tarjetas y encontrar una es imposible.
class CatalogGroup {
  const CatalogGroup({required this.items});

  /// Las tallas, ya ordenadas. Un producto sin tallas es un grupo de uno.
  final List<StandCatalogItem> items;

  StandCatalogItem get first => items.first;

  /// Un grupo de uno se pinta como el producto que es, no como un modelo.
  bool get hasVariants => items.length > 1 || first.isVariant;

  String get id => first.groupId;
  String get name => first.groupName;

  /// Suma de todas las tallas. Es lo que se enseña en la tarjeta: lo que hace
  /// falta saber de un vistazo es si queda polera, no si queda la M.
  int get quantity => items.fold(0, (sum, i) => sum + i.quantity);

  /// Cuántas tallas están por debajo de su umbral, o en negativo.
  int get alerts => items.where((i) => i.isLow || i.isNegative).length;

  bool get hasNegative => items.any((i) => i.isNegative);

  /// Rango de precios del modelo, para la tarjeta agrupada.
  (double, double) get priceRange {
    final prices = items.map((i) => i.price).toList()..sort();
    return (prices.first, prices.last);
  }
}

/// Agrupa las líneas del catálogo por modelo, conservando el orden de tallas.
///
/// El orden de los grupos sigue al de la lista que entra —ya viene ordenada
/// por nombre— para que filtrar o buscar no reordene la pantalla entera.
List<CatalogGroup> groupCatalog(List<StandCatalogItem> items) {
  final byGroup = <String, List<StandCatalogItem>>{};
  final order = <String>[];

  for (final item in items) {
    final key = item.groupId;
    if (!byGroup.containsKey(key)) order.add(key);
    byGroup.putIfAbsent(key, () => []).add(item);
  }

  return [
    for (final key in order)
      CatalogGroup(
        items: byGroup[key]!
          // Por `variantOrder` y no alfabéticamente: si no, las tallas salen
          // L, M, S, XL, que no es como nadie las busca.
          ..sort((a, b) {
            final byOrder = a.variantOrder.compareTo(b.variantOrder);
            return byOrder != 0
                ? byOrder
                : a.productName.compareTo(b.productName);
          }),
      ),
  ];
}

/// Las tallas de un modelo, para elegir de cuál descontar.
///
/// Se abre al tocar la tarjeta agrupada. Cuesta un toque más que la salida
/// directa de un producto suelto, y no hay forma de evitarlo: hay que decir
/// qué talla se vendió.
class VariantSheet extends StatelessWidget {
  const VariantSheet({
    super.key,
    required this.group,
    required this.onExit,
    required this.onMore,
    required this.busyIds,
  });

  final CatalogGroup group;

  /// Descontar una unidad de esa talla.
  final void Function(StandCatalogItem) onExit;

  /// Abrir la hoja completa de movimientos para esa talla.
  final void Function(StandCatalogItem) onMore;

  final Set<String> busyIds;

  static Future<void> show(
    BuildContext context, {
    required CatalogGroup group,
    required void Function(StandCatalogItem) onExit,
    required void Function(StandCatalogItem) onMore,
    required Set<String> busyIds,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VariantSheet(
        group: group,
        onExit: onExit,
        onMore: onMore,
        busyIds: busyIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.xl, 0, Space.xl, Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.xs),
                Text(
                  '${group.quantity} unidades en ${group.items.length} tallas',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: group.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = group.items[i];
                final busy = busyIds.contains(item.productId);

                return ListTile(
                  // La talla, grande: es lo único que distingue una fila de
                  // otra y se busca con el dedo, no leyendo.
                  leading: SizedBox(
                    width: 44,
                    child: Text(
                      item.shortLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  title: Text('${item.quantity} unidades'),
                  subtitle: Text(
                    [
                      if (item.price > 0) '\$${item.price.round()}',
                      if (item.isNegative) 'saldo negativo',
                      if (!item.isNegative && item.isLow) 'stock bajo',
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: item.isNegative
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: busy ? null : () => onMore(item),
                        icon: const Icon(Icons.tune),
                        tooltip: 'Otros movimientos',
                      ),
                      FilledButton(
                        onPressed: busy ? null : () => onExit(item),
                        child: const Text('−1'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: Space.md),
        ],
      ),
    );
  }
}
