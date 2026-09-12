import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/utils/formatters.dart';
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
      // Altura acotada: con trece tallas la hoja se comía la pantalla entera
      // y tapaba el producto que se está mirando.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
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
                  Text(
                    group.name,
                    style: theme.textTheme.titleLarge,
                    // Un nombre largo empujaba el resto fuera de la hoja.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${group.quantity} unidades · ${group.items.length} tallas',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: group.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _VariantRow(
                  item: group.items[i],
                  busy: busyIds.contains(group.items[i].productId),
                  onExit: () => onExit(group.items[i]),
                  onMore: () => onMore(group.items[i]),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
  }
}

/// Una talla dentro de la hoja.
///
/// Se construye con un `Row` propio y no con `ListTile`: el `trailing` de un
/// `ListTile` no está pensado para dos botones, y en un móvil estrecho
/// desbordaba por la derecha llevándose el diseño por delante.
class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.item,
    required this.busy,
    required this.onExit,
    required this.onMore,
  });

  final StandCatalogItem item;
  final bool busy;
  final VoidCallback onExit;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = theme.colorScheme.error;

    final notes = [
      if (item.price > 0) Fmt.money(item.price),
      if (item.isNegative)
        'saldo negativo'
      else if (item.isLow)
        'stock bajo',
    ].join(' · ');

    return InkWell(
      // Tocar la fila abre los demás movimientos: el botón pequeño de al lado
      // hace lo mismo, pero con un dedo y prisa se acierta antes en la fila.
      onTap: busy ? null : onMore,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter, vertical: Space.sm),
        child: Row(
          children: [
            // La talla, en una caja de ancho fijo para que todas las filas
            // queden alineadas. Las largas («Única») se encogen en vez de
            // empujar al resto.
            SizedBox(
              width: 46,
              child: Text(
                item.shortLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.quantity}',
                    maxLines: 1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: item.isNegative ? danger : null,
                    ),
                  ),
                  if (notes.isNotEmpty)
                    Text(
                      notes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: item.isNegative ? danger : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            // Compacto a propósito: dos botones de tamaño normal no caben
            // junto al texto en un teléfono estrecho.
            IconButton(
              onPressed: busy ? null : onMore,
              icon: const Icon(Icons.tune, size: 20),
              tooltip: 'Otros movimientos',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: Space.xs),
            SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: busy || item.quantity <= 0 ? null : onExit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('−1'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
