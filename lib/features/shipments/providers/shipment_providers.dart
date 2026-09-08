import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../data/models/shipment.dart';
import '../../../data/models/shipment_item.dart';
import '../../../services/service_providers.dart';
import '../../stands/providers/stand_providers.dart';

/// Encomiendas del puesto activo, la más reciente primero.
///
/// Se filtra por puesto activo igual que el resto de las pestañas operativas:
/// un vendedor solo ve las de sus puestos porque RLS ya lo limita, y un
/// administrador ve las de aquel que esté mirando y cambia con el selector del
/// título. Mostrarle todas de golpe convertiría la lista en un cajón.
final shipmentsProvider =
    FutureProvider.autoDispose<List<Shipment>>((ref) async {
  final stand = await ref.watch(activeStandProvider.future);
  if (stand == null) return const [];
  return ref.watch(shipmentServiceProvider).fetchShipments(standId: stand.id);
});

/// Encomiendas que el puesto todavía no ha confirmado.
///
/// Es lo que el vendedor tiene pendiente de abrir y revisar; alimenta el
/// contador de la pestaña.
final pendingShipmentsProvider =
    FutureProvider.autoDispose<List<Shipment>>((ref) async {
  final stand = await ref.watch(activeStandProvider.future);
  if (stand == null) return const [];
  return ref.watch(shipmentServiceProvider).fetchShipments(
        standId: stand.id,
        status: ShipmentStatus.enviado,
      );
});

/// Una encomienda concreta, con sus totales ya agregados.
final shipmentDetailProvider =
    FutureProvider.autoDispose.family<Shipment?, String>((ref, id) async {
  return ref.watch(shipmentServiceProvider).fetchShipment(id);
});

/// Líneas de una encomienda concreta.
final shipmentItemsProvider =
    FutureProvider.autoDispose.family<List<ShipmentItem>, String>(
        (ref, shipmentId) async {
  return ref.watch(shipmentServiceProvider).fetchItems(shipmentId);
});

/// Cuántos productos esperan que el administrador confirme su precio.
///
/// Un producto que registró un vendedor sin saber cuánto vale se vendería a 0
/// si nadie lo completa. Sin este contador se pierde entre los demás.
final pendingPriceCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(shipmentServiceProvider).pendingPriceCount();
});
