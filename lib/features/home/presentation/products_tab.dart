import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/inventory_movement.dart';
import '../../../data/models/stand.dart';
import '../../../data/models/stand_catalog_item.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../../../shared/widgets/undo_snack_bar.dart';
import '../../movements/presentation/movement_sheet.dart';
import '../../products/presentation/product_form_sheet.dart';
import '../../products/providers/product_providers.dart';
import '../../movements/providers/movement_providers.dart';
import '../../stands/providers/stand_providers.dart';
import 'variant_sheet.dart';

/// Productos del puesto activo (§4.1). Es la pantalla que más se usa.
///
/// Tarjetas en rejilla en lugar de lista: el trabajador reconoce el producto
/// por su forma y color antes que por leer un renglón. El botón de salida
/// descuenta **de un solo toque**, con deshacer durante unos segundos; el
/// toque en la tarjeta abre la hoja completa para otras cantidades o tipos.
class ProductsTab extends ConsumerStatefulWidget {
  const ProductsTab({super.key});

  @override
  ConsumerState<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<ProductsTab> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _onlyAlerts = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<StandCatalogItem> _filter(List<StandCatalogItem> items) {
    var result = items;
    if (_onlyAlerts) {
      result = result.where((i) => i.isLow || i.isNegative).toList();
    }
    if (_search.trim().isEmpty) return result;

    final q = _search.trim().toLowerCase();
    return result
        .where(
          (i) =>
              i.productName.toLowerCase().contains(q) ||
              (i.sku?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  /// Descuento de una unidad, sin confirmación previa.
  Future<void> _quickExit(StandCatalogItem item, Stand stand) async {
    final pending = ref.read(pendingExitsProvider.notifier);
    if (pending.contains(item.productId)) return;

    HapticFeedback.mediumImpact();
    pending.start(item.productId);

    final catalog = ref.read(activeStandCatalogProvider.notifier);
    // El número baja al instante; el saldo real lo confirma el trigger.
    catalog.applyDelta(item.productId, -1);

    try {
      final movement = await ref
          .read(movementServiceProvider)
          .registerExit(productId: item.productId, standId: stand.id);
      if (!mounted) return;
      _showUndo(movement, item);
      await catalog.refresh();
      ref.invalidate(movementHistoryProvider);
    } on AppException catch (e) {
      if (!mounted) return;
      // Falló: devolver el número a su sitio en vez de dejar un dato falso.
      catalog.applyDelta(item.productId, 1);
      _snack(e.message, error: true);
    } finally {
      pending.finish(item.productId);
    }
  }

  void _showUndo(InventoryMovement movement, StandCatalogItem item) {
    UndoSnackBar.show(
      context,
      message: '−1 · ${item.productName}',
      onUndo: () => _undo(movement, item),
    );
  }

  /// Deshacer no borra: registra el movimiento contrario (§19). El historial
  /// mostrará la salida y su devolución, que es lo que de verdad ocurrió.
  Future<void> _undo(InventoryMovement movement, StandCatalogItem item) async {
    final catalog = ref.read(activeStandCatalogProvider.notifier);
    catalog.applyDelta(item.productId, 1);
    try {
      await ref.read(movementServiceProvider).compensate(movement);
      if (!mounted) return;
      await catalog.refresh();
      ref.invalidate(movementHistoryProvider);
      _snack('Descuento anulado');
    } on AppException catch (e) {
      if (!mounted) return;
      catalog.applyDelta(item.productId, -1);
      _snack(e.message, error: true);
    }
  }

  /// Hoja completa: otras cantidades, entradas, devoluciones y ajustes.
  Future<void> _openSheet(StandCatalogItem item, Stand stand) async {
    final registered = await MovementSheet.show(
      context,
      item: item,
      standId: stand.id,
    );
    if (registered == null || !mounted) return;

    HapticFeedback.mediumImpact();
    final catalog = ref.read(activeStandCatalogProvider.notifier);
    catalog.applyDelta(item.productId, registered.delta);
    _snack('${registered.type.label} · ${item.productName}');

    await catalog.refresh();
    ref.invalidate(movementHistoryProvider);
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  /// Abre las tallas de un modelo para descontar de una de ellas.
  Future<void> _openVariants(CatalogGroup group, Stand stand) async {
    await VariantSheet.show(
      context,
      group: group,
      busyIds: ref.read(pendingExitsProvider),
      onExit: (item) {
        // Se cierra la hoja antes de descontar: el aviso de deshacer sale
        // abajo, y con la hoja abierta quedaría tapado justo cuando hay unos
        // segundos para pulsarlo.
        Navigator.of(context).pop();
        _quickExit(item, stand);
      },
      onMore: (item) {
        Navigator.of(context).pop();
        _openSheet(item, stand);
      },
    );
  }

  Future<void> _newProduct(Stand stand) async {
    final created = await ProductFormSheet.show(context, standId: stand.id);
    if (created == null || !mounted) return;
    await ref.read(activeStandCatalogProvider.notifier).refresh();
  }

  /// Editar es de staff, y RLS lo aplica. El vendedor solo opera movimientos.
  Future<void> _editProduct(StandCatalogItem item) async {
    final product = await ref
        .read(catalogServiceProvider)
        .fetchProduct(item.productId);
    if (product == null || !mounted) return;

    final saved = await ProductFormSheet.show(context, product: product);
    if (saved == null || !mounted) return;
    await ref.read(activeStandCatalogProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final canOperate = profile != null;
    final isStaff = profile?.isStaff ?? false;
    final activeStand = ref.watch(activeStandProvider);
    final catalog = ref.watch(activeStandCatalogProvider);
    final pending = ref.watch(pendingExitsProvider);

    return Scaffold(
      // También el vendedor: la mercadería llega muchas veces sin encomienda
      // registrada, y si solo staff pudiera crear productos, lo que llegó se
      // quedaría fuera del sistema hasta que alguien contestara el teléfono.
      // Lo que él cree queda con el precio por confirmar (migración 0013).
      // Redondo y sin texto: la etiqueta ocupaba sitio sobre una lista que se
      // recorre a diario, y lo que hace se entiende por el signo y el sitio.
      // El nombre completo vive en el tooltip y en el título de la hoja.
      floatingActionButton: canOperate && activeStand.value != null
          ? FloatingActionButton(
              onPressed: () => _newProduct(activeStand.value!),
              tooltip: isStaff ? 'Nuevo producto' : 'Registrar lo que llegó',
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          // Un producto sin precio se vendería a cero. El aviso va donde está
          // quien puede arreglarlo, no escondido en otra pantalla.
          if (isStaff) const _PendingPriceBanner(),
          _SearchBar(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            onClear: () {
              _searchCtrl.clear();
              setState(() => _search = '');
            },
            alertsOn: _onlyAlerts,
            onToggleAlerts: () => setState(() => _onlyAlerts = !_onlyAlerts),
            alertCount:
                catalog.value?.where((i) => i.isLow || i.isNegative).length ??
                0,
          ),
          const Divider(height: 1),
          Expanded(
            child: catalog.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudo cargar el catálogo',
                detail: e is AppException ? e.message : '$e',
                tone: EmptyTone.danger,
                onAction: () => ref.invalidate(activeStandCatalogProvider),
              ),
              data: (all) {
                final stand = activeStand.value;
                if (stand == null) {
                  return const EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'Sin puesto asignado',
                    detail: 'Pide a un administrador que te asigne un puesto.',
                  );
                }
                if (all.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'El puesto no tiene productos',
                    detail:
                        'Asigna productos a "${stand.name}", o registra una '
                        'entrada para que aparezcan aquí.',
                    onAction: () => ref.invalidate(activeStandCatalogProvider),
                  );
                }

                final items = _filter(all);
                final groups = groupCatalog(items);
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off,
                    title: 'Sin resultados',
                    detail: _onlyAlerts
                        ? 'Ningún producto con stock bajo o negativo.'
                        : 'Ningún producto coincide con "$_search".',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(activeStandCatalogProvider.notifier).refresh(),
                  child: ContentWidth(
                    maxWidth: Sizes.wideContentMax,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        Space.md,
                        Space.md,
                        Space.md,
                        88,
                      ),
                      // Dos columnas en móvil; en pantallas anchas crece solo,
                      // sin decidir puntos de ruptura a mano.
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisSpacing: Space.md,
                            crossAxisSpacing: Space.md,
                            mainAxisExtent: 212,
                          ),
                      itemCount: groups.length,
                      itemBuilder: (context, i) {
                        final group = groups[i];

                        // Un modelo con tallas no se descuenta de un toque:
                        // hay que decir qué talla se vendió, y eso no se
                        // puede adivinar.
                        if (group.hasVariants) {
                          return _GroupCard(
                            group: group,
                            onTap: () => _openVariants(group, stand),
                          );
                        }

                        final item = group.first;
                        return _ProductCard(
                          item: item,
                          canOperate: canOperate,
                          busy: pending.contains(item.productId),
                          onQuickExit: () => _quickExit(item, stand),
                          onMore: () => _openSheet(item, stand),
                          onEdit: isStaff ? () => _editProduct(item) : null,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de un modelo con tallas.
///
/// No lleva botón de salida directa a propósito: descontar exige saber qué
/// talla se vendió, y ponerlo aquí obligaría a elegir una por defecto —que
/// sería la equivocada la mitad de las veces y dejaría el stock mal sin que
/// nadie se entere—.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final CatalogGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;
    final first = group.first;
    final (minPrice, _) = group.priceRange;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // El mismo esqueleto que una tarjeta de producto —avatar y
              // total arriba, nombre, precio, acción abajo—. Con estructura
              // propia rompía el ritmo de la rejilla: dejaba un hueco donde
              // las demás tienen el precio y el botón.
              Row(
                children: [
                  ProductAvatar(
                    imageUrl: first.parentImageUrl ?? first.imageUrl,
                    productIcon: first.parentIcon ?? first.productIcon,
                    categoryIcon: first.categoryIcon,
                    size: 44,
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${group.quantity}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: group.hasNegative ? semantic.danger : null,
                        ),
                      ),
                      Text('unidades', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                group.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              Row(
                children: [
                  // «Desde» y no el rango completo: «4.990 $–6.990 $» no cabe
                  // ni en una pantalla de escritorio y se cortaba a la mitad,
                  // que es peor que no enseñarlo. El detalle está dentro.
                  Expanded(
                    child: minPrice > 0
                        ? Text(
                            'desde ${Fmt.money(minPrice)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : Text('Sin precio',
                            style: theme.textTheme.labelSmall),
                  ),
                  if (group.hasNegative)
                    Icon(Icons.priority_high, size: 16, color: semantic.danger)
                  else if (group.alerts > 0)
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: semantic.warning),
                ],
              ),
              const SizedBox(height: Space.sm),
              // Ocupa el sitio del botón de salida de las demás tarjetas, y
              // dice lo que va a pasar: sin esto nada indicaba que la tarjeta
              // se puede tocar.
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onTap,
                  child: Text('${group.items.length} tallas'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.canOperate,
    required this.busy,
    required this.onQuickExit,
    required this.onMore,
    this.onEdit,
  });

  final StandCatalogItem item;
  final bool canOperate;
  final bool busy;
  final VoidCallback onQuickExit;
  final VoidCallback onMore;

  /// null para un vendedor: editar el catálogo es de staff.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    final stockColor = item.isNegative
        ? semantic.danger
        : item.isLow
        ? semantic.warning
        : theme.colorScheme.onSurface;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Toque en la tarjeta: hoja completa (otras cantidades, entradas…).
        onTap: canOperate ? onMore : null,
        // Pulsación larga: editar el producto. No estorba el descuento rápido.
        onLongPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.md,
            Space.md,
            Space.md,
            Space.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cascada: foto propia -> icono de la categoría -> genérico.
                  ProductAvatar(
                    imageUrl: item.imageUrl,
                    productIcon: item.productIcon,
                    categoryIcon: item.categoryIcon,
                    size: 44,
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _AnimatedCount(
                        value: item.quantity,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: stockColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text('unidades', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),

              Text(
                item.productName,
                style: theme.textTheme.bodyLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const Spacer(),

              // El precio manda visualmente: es el dato que el trabajador
              // canta al cliente y el que más consulta.
              Row(
                children: [
                  Expanded(
                    child: item.price > 0
                        ? Text(
                            Fmt.money(item.price),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Text('Sin precio', style: theme.textTheme.labelSmall),
                  ),
                  if (item.isNegative)
                    Icon(Icons.priority_high, size: 16, color: semantic.danger)
                  else if (item.isLow)
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: semantic.warning,
                    ),
                  if (!item.inCatalog)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.xs),
                      child: Tooltip(
                        message: 'Fuera del catálogo de este puesto',
                        child: Icon(
                          Icons.help_outline,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: Space.sm),
              _DiscountButton(
                enabled: canOperate && !busy,
                busy: busy,
                onPressed: onQuickExit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón de descuento inmediato. Ancho completo para que sea difícil fallarlo
/// con el pulgar operando de pie.
class _DiscountButton extends StatelessWidget {
  const _DiscountButton({
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton.tonal(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
        ),
        child: busy
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.remove, size: 18),
                  const SizedBox(width: Space.xs + 2),
                  Text('1 salida', style: theme.textTheme.labelMedium),
                ],
              ),
      ),
    );
  }
}

/// Cifra que transita al cambiar en lugar de saltar de golpe.
class _AnimatedCount extends StatelessWidget {
  const _AnimatedCount({required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // Sin `begin`: arranca en el valor actual y anima solo cuando `end`
      // cambia. Fijar `begin` haría que nunca se moviera.
      tween: Tween(end: value.toDouble()),
      duration: Motion.normal,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) =>
          Text(Fmt.number(animated.round()), style: style),
    );
  }
}

/// Cuántos productos esperan precio, con acceso a completarlos.
///
/// Un vendedor registra lo que le llegó sin saber cuánto vale; si nadie lo
/// confirma, ese producto se vende a cero. Avisar sin dar el camino sería
/// dejar el problema a la vista y a medias, así que el aviso se toca.
class _PendingPriceBanner extends ConsumerWidget {
  const _PendingPriceBanner();

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final pending =
        await ref.read(catalogServiceProvider).fetchPendingPriceProducts();
    if (!context.mounted || pending.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const SectionHeader(label: 'Productos sin precio'),
            for (final product in pending)
              ListTile(
                leading: ProductAvatar(
                  imageUrl: product.imageUrl,
                  productIcon: product.icon,
                  size: 36,
                ),
                title: Text(product.name),
                subtitle: Text(
                  product.categoryName ?? 'Sin categoría',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  Navigator.of(context).pop();
                  final saved =
                      await ProductFormSheet.show(context, product: product);
                  if (saved == null) return;
                  ref.invalidate(pendingPriceCountProvider);
                  ref.invalidate(activeStandCatalogProvider);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingPriceCountProvider).value ?? 0;
    if (count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = theme.semantic.warning;

    return Material(
      color: color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () => _open(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.gutter, vertical: Space.sm),
          child: Row(
            children: [
              Icon(Icons.sell, size: 18, color: color),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 producto sin precio: se vendería en \$0'
                      : '$count productos sin precio: se venderían en \$0',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.alertsOn,
    required this.onToggleAlerts,
    required this.alertCount,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool alertsOn;
  final VoidCallback onToggleAlerts;
  final int alertCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ContentWidth(
      maxWidth: Sizes.wideContentMax,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.md,
          Space.gutter,
          Space.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar producto o código',
                  prefixIcon: const Icon(Icons.search, size: Sizes.icon),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: onClear,
                        ),
                ),
              ),
            ),
            if (alertCount > 0) ...[
              const SizedBox(width: Space.sm),
              Tooltip(
                message: alertsOn
                    ? 'Ver todos los productos'
                    : 'Ver solo stock bajo o negativo',
                child: InkWell(
                  onTap: onToggleAlerts,
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    decoration: BoxDecoration(
                      color: alertsOn
                          ? theme.semantic.warningSurface
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(
                        color: alertsOn
                            ? theme.semantic.warning
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: theme.semantic.warning,
                        ),
                        const SizedBox(width: Space.xs + 2),
                        Text(
                          '$alertCount',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.semantic.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
