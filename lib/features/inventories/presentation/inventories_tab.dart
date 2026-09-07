import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/inventory.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../stands/providers/stand_providers.dart';
import '../providers/inventory_providers.dart';
import 'inventory_count_screen.dart';

/// Jornadas de inventario del puesto activo (§8).
class InventoriesTab extends ConsumerStatefulWidget {
  const InventoriesTab({super.key});

  @override
  ConsumerState<InventoriesTab> createState() => _InventoriesTabState();
}

class _InventoriesTabState extends ConsumerState<InventoriesTab> {
  bool _opening = false;

  Future<void> _open() async {
    final stand = ref.read(activeStandProvider).value;
    if (stand == null) return;

    setState(() => _opening = true);
    try {
      final id = await ref
          .read(inventoryServiceProvider)
          .openInventory(standId: stand.id);
      if (!mounted) return;

      ref.invalidate(inventoriesProvider);
      ref.invalidate(openInventoryProvider);
      setState(() => _opening = false);
      _goTo(id);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
    }
  }

  void _goTo(String inventoryId) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => InventoryCountScreen(inventoryId: inventoryId),
        ))
        .then((_) {
          if (!mounted) return;
          ref.invalidate(inventoriesProvider);
          ref.invalidate(openInventoryProvider);
        });
  }

  @override
  Widget build(BuildContext context) {
    final inventories = ref.watch(inventoriesProvider);
    final open = ref.watch(openInventoryProvider).value;

    return Scaffold(
      body: inventories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'No se pudieron cargar los inventarios',
          detail: e is AppException ? e.message : '$e',
          tone: EmptyTone.danger,
          onAction: () => ref.invalidate(inventoriesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.fact_check_outlined,
              title: 'Sin inventarios',
              detail: 'Abre una jornada para contar físicamente lo que hay '
                  'en el puesto y compararlo con el sistema.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(inventoriesProvider),
            child: ContentWidth(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _InventoryRow(
                  inventory: list[i],
                  onTap: () => _goTo(list[i].id),
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _opening
            ? null
            : open != null
                ? () => _goTo(open.id)
                : _open,
        icon: _opening
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(open != null ? Icons.play_arrow : Icons.add),
        label: Text(open != null ? 'Continuar conteo' : 'Nuevo inventario'),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({required this.inventory, required this.onTap});

  final Inventory inventory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;
    final withDiff = inventory.itemsWithDifference ?? 0;

    final (icon, color, label) = switch (inventory.status) {
      InventoryStatus.abierto => (
          Icons.pending_actions,
          semantic.info,
          'En curso',
        ),
      InventoryStatus.finalizado when withDiff > 0 => (
          Icons.rule,
          semantic.danger,
          '$withDiff con diferencia',
        ),
      InventoryStatus.finalizado => (
          Icons.verified,
          semantic.positive,
          'Cuadrado',
        ),
      InventoryStatus.anulado => (
          Icons.block,
          theme.colorScheme.onSurfaceVariant,
          'Anulado',
        ),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter, vertical: Space.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('#${inventory.code}',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(width: Space.sm),
                      StatusPill(label: label, color: color),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    [
                      Fmt.dateTime(inventory.startedAt),
                      if (inventory.profileName != null)
                        inventory.profileName!,
                    ].join(' · '),
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${inventory.itemsCounted ?? 0}/${inventory.itemsTotal ?? 0}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text('contados', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(width: Space.xs),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}
