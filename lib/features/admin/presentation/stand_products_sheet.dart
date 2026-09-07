import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/product.dart';
import '../../../data/models/stand.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../../products/providers/product_providers.dart';
import '../../stands/providers/stand_providers.dart';
import '../providers/admin_providers.dart';

/// Qué productos maneja un puesto.
///
/// Define lo que se cuenta en un inventario físico y lo que aparece por
/// defecto al registrar una salida. **No limita dónde puede haber stock**: si
/// llega mercadería por traslado a un puesto sin asignar, el saldo se registra
/// igual y aparece marcado como fuera de catálogo.
class StandProductsSheet extends ConsumerStatefulWidget {
  const StandProductsSheet({super.key, required this.stand});

  final Stand stand;

  static Future<void> show(BuildContext context, {required Stand stand}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StandProductsSheet(stand: stand),
    );
  }

  @override
  ConsumerState<StandProductsSheet> createState() => _StandProductsSheetState();
}

class _StandProductsSheetState extends ConsumerState<StandProductsSheet> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  /// Ids en proceso de guardado, para no encadenar toques sobre el mismo.
  final _saving = <String>{};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggle(Product product, bool assigned) async {
    if (_saving.contains(product.id)) return;
    setState(() => _saving.add(product.id));

    final service = ref.read(catalogServiceProvider);
    try {
      if (assigned) {
        await service.removeProductFromStand(
          standId: widget.stand.id,
          productId: product.id,
        );
      } else {
        await service.assignProductsToStand(
          standId: widget.stand.id,
          productIds: [product.id],
        );
      }
      if (!mounted) return;
      ref.invalidate(standProductIdsProvider(widget.stand.id));
      // El catálogo del puesto activo cambia si es este mismo.
      await ref.read(activeStandCatalogProvider.notifier).refresh();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _saving.remove(product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = ref.watch(productsProvider);
    final assignedIds = ref.watch(standProductIdsProvider(widget.stand.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Productos del puesto', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  '${widget.stand.name} · '
                  '${assignedIds.value?.length ?? 0} asignados',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Space.md),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar producto',
                    prefixIcon: const Icon(Icons.search, size: Sizes.icon),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudo cargar el catálogo',
                detail: e is AppException ? e.message : '$e',
                tone: EmptyTone.danger,
                onAction: () => ref.invalidate(productsProvider),
              ),
              data: (all) {
                final assigned = assignedIds.value ?? const <String>{};
                final q = _search.trim().toLowerCase();
                final list = q.isEmpty
                    ? all
                    : all
                          .where(
                            (p) =>
                                p.name.toLowerCase().contains(q) ||
                                (p.sku?.toLowerCase().contains(q) ?? false),
                          )
                          .toList();

                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off,
                    title: 'Sin resultados',
                    detail: all.isEmpty
                        ? 'No hay productos en el catálogo todavía.'
                        : 'Ningún producto coincide con "$_search".',
                  );
                }

                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: Space.xxl),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final product = list[i];
                    final isAssigned = assigned.contains(product.id);
                    return SwitchListTile(
                      value: isAssigned,
                      onChanged: _saving.contains(product.id)
                          ? null
                          : (_) => _toggle(product, isAssigned),
                      secondary: ProductAvatar(
                        imageUrl: product.imageUrl,
                        productIcon: product.icon,
                        size: 40,
                      ),
                      title: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if (product.sku != null) product.sku!,
                          if (product.price > 0) Fmt.money(product.price),
                        ].join(' · '),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
