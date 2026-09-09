import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/shipment.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../stands/providers/stand_providers.dart';
import '../providers/shipment_providers.dart';
import 'dispatch_shipment_screen.dart';
import 'receive_shipment_screen.dart';

/// Encomiendas del puesto activo: lo que viene en camino y lo que ya llegó.
///
/// El administrador compra en Santiago y despacha en el momento. El vendedor
/// abre el paquete y confirma qué llegó de verdad — que es donde el sistema
/// aporta algo frente a preguntar por teléfono.
class ShipmentsTab extends ConsumerWidget {
  const ShipmentsTab({super.key});

  void _open(BuildContext context, WidgetRef ref, Shipment shipment) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ReceiveShipmentScreen(shipmentId: shipment.id),
        ))
        .then((_) {
          ref.invalidate(shipmentsProvider);
          ref.invalidate(pendingShipmentsProvider);
        });
  }

  Future<void> _dispatch(BuildContext context, WidgetRef ref) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const DispatchShipmentScreen()),
    );
    if (sent != true) return;
    ref.invalidate(shipmentsProvider);
    ref.invalidate(pendingShipmentsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shipments = ref.watch(shipmentsProvider);
    final isStaff = ref.watch(currentProfileProvider).value?.isStaff ?? false;
    final hasStand = ref.watch(activeStandProvider).value != null;

    return Scaffold(
      body: Column(
        children: [
          // Un producto sin precio confirmado se vendería a 0 si nadie lo
          // completa. El aviso es para quien puede arreglarlo.
          if (isStaff) const _PendingPriceBanner(),
          Expanded(
            child: shipments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudieron cargar las encomiendas',
                detail: e is AppException ? e.message : '$e',
                tone: EmptyTone.danger,
                onAction: () => ref.invalidate(shipmentsProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  // Esta pestaña solo sirve cuando alguien registró el envío.
                  // No siempre pasa: muchas veces el paquete llega sin nada
                  // apuntado, y entonces el camino no está aquí. Decirlo
                  // evita que el vendedor se quede esperando una encomienda
                  // que nunca va a aparecer.
                  return EmptyState(
                    icon: Icons.redeem,
                    title: 'Sin encomiendas',
                    detail: isStaff
                        ? 'Cuando despaches mercadería a este puesto, '
                            'aparecerá aquí hasta que el vendedor confirme '
                            'qué llegó.\n\n'
                            'Si mandas un paquete sin registrarlo, el vendedor '
                            'puede darlo de alta directamente en Productos.'
                        : 'Aquí aparece solo la mercadería que te envíen '
                            'registrada en el sistema.\n\n'
                            'Si te llegó un paquete que no está aquí, '
                            'regístralo en Productos con el botón +.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(shipmentsProvider);
                    ref.invalidate(pendingShipmentsProvider);
                  },
                  child: ContentWidth(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _ShipmentRow(
                        shipment: list[i],
                        onTap: () => _open(context, ref, list[i]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // Solo staff despacha, y RLS lo aplica igualmente.
      floatingActionButton: isStaff && hasStand
          ? FloatingActionButton.extended(
              onPressed: () => _dispatch(context, ref),
              icon: const Icon(Icons.redeem),
              label: const Text('Despachar'),
            )
          : null,
    );
  }
}

/// Cuántos productos esperan precio, y el acceso para completarlos.
class _PendingPriceBanner extends ConsumerWidget {
  const _PendingPriceBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingPriceCountProvider).value ?? 0;
    if (count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = theme.semantic.warning;

    return Material(
      color: color.withValues(alpha: 0.12),
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
                    ? '1 producto registrado sin precio'
                    : '$count productos registrados sin precio',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShipmentRow extends StatelessWidget {
  const _ShipmentRow({required this.shipment, required this.onTap});

  final Shipment shipment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    final (icon, color, label) = switch (shipment.status) {
      ShipmentStatus.enviado => (
          Icons.redeem,
          semantic.info,
          'En camino',
        ),
      // Un faltante no es un detalle: es lo que hay que reclamar, así que se
      // ve desde la lista sin tener que abrir la encomienda.
      ShipmentStatus.recibido when shipment.hasMissing => (
          Icons.warning_amber_rounded,
          semantic.danger,
          'Faltó ${shipment.missingTotal}',
        ),
      ShipmentStatus.recibido => (
          Icons.inventory_2,
          semantic.positive,
          'Recibida',
        ),
      ShipmentStatus.anulado => (
          Icons.block,
          theme.colorScheme.onSurfaceVariant,
          'Anulada',
        ),
    };

    final title = shipment.blind
        ? 'Paquete sin detallar'
        : '${shipment.itemCount ?? 0} producto(s)';

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
                      Flexible(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      StatusPill(label: label, color: color),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    [
                      Fmt.dateTime(shipment.createdAt),
                      if (shipment.createdByName != null)
                        shipment.createdByName!,
                    ].join(' · '),
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            if (!shipment.blind)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    shipment.isPending
                        ? '${shipment.sentTotal ?? 0}'
                        : '${shipment.receivedTotal ?? 0}/${shipment.sentTotal ?? 0}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    shipment.isPending ? 'enviadas' : 'recibidas',
                    style: theme.textTheme.labelSmall,
                  ),
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
