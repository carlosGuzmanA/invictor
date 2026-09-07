import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/inventory.dart';
import '../../../data/models/inventory_item.dart';
import '../../../services/service_providers.dart';
import '../../stands/providers/stand_providers.dart';

/// Jornadas de inventario del puesto activo, la más reciente primero.
final inventoriesProvider =
    FutureProvider.autoDispose<List<Inventory>>((ref) async {
  final stand = await ref.watch(activeStandProvider.future);
  if (stand == null) return const [];
  return ref.watch(inventoryServiceProvider).fetchInventories(standId: stand.id);
});

/// Jornada abierta del puesto activo, si la hay. La base garantiza que solo
/// puede existir una a la vez por puesto.
final openInventoryProvider =
    FutureProvider.autoDispose<Inventory?>((ref) async {
  final stand = await ref.watch(activeStandProvider.future);
  if (stand == null) return null;
  return ref.watch(inventoryServiceProvider).fetchOpenInventory(stand.id);
});

/// Detalle de una jornada concreta.
final inventoryDetailProvider =
    FutureProvider.autoDispose.family<Inventory?, String>((ref, id) async {
  return ref.watch(inventoryServiceProvider).fetchInventory(id);
});

/// Productos a contar en una jornada.
final inventoryItemsProvider =
    FutureProvider.autoDispose.family<List<InventoryItem>, String>(
        (ref, inventoryId) async {
  return ref.watch(inventoryServiceProvider).fetchItems(inventoryId);
});
