import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/product.dart';
import '../../../data/models/shipment.dart';
import '../../../data/models/shipment_item.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../../products/presentation/product_form_sheet.dart';
import '../providers/shipment_providers.dart';

/// Recibir una encomienda: confirmar qué llegó de verdad.
///
/// Se puede recibir de menos. Si se despacharon 10 y llegaron 8, se
/// registran 8 y el faltante queda en la encomienda — **no genera
/// movimiento**, porque lo que no llegó nunca estuvo en el puesto y
/// descontarlo sería inventar una salida.
///
/// En una encomienda a ciegas el contenido lo descubre el vendedor: añade los
/// productos que encuentra, y los que no estén en el catálogo los crea. Si no
/// sabe el precio, lo deja en blanco y queda marcado para que el
/// administrador lo complete.
class ReceiveShipmentScreen extends ConsumerStatefulWidget {
  const ReceiveShipmentScreen({super.key, required this.shipmentId});

  final String shipmentId;

  @override
  ConsumerState<ReceiveShipmentScreen> createState() =>
      _ReceiveShipmentScreenState();
}

class _ReceiveShipmentScreenState
    extends ConsumerState<ReceiveShipmentScreen> {
  /// productId -> cantidad que el vendedor confirma haber recibido.
  final Map<String, int> _received = {};

  /// Productos añadidos a mano en una encomienda a ciegas.
  final Map<String, Product> _added = {};

  bool _busy = false;
  bool _prefilled = false;
  String? _error;

  /// Preinicializa con lo despachado: el caso normal es que llegue todo, y
  /// obligar a teclear cada cantidad convertiría lo habitual en el trabajo
  /// más lento.
  void _prefill(List<ShipmentItem> items) {
    if (_prefilled) return;
    _prefilled = true;
    for (final item in items) {
      if (item.sentQty != null) _received[item.productId] = item.sentQty!;
    }
  }

  Future<void> _addFromCatalog() async {
    final product = await ProductFormSheet.show(context);
    if (product == null || !mounted) return;

    setState(() {
      _added[product.id] = product;
      _received[product.id] = _received[product.id] ?? 1;
    });
  }

  void _setQuantity(String productId, int quantity, {bool removable = false}) {
    setState(() {
      if (quantity <= 0 && removable) {
        _received.remove(productId);
        _added.remove(productId);
      } else {
        _received[productId] = quantity < 0 ? 0 : quantity;
      }
    });
  }

  /// Muestra el fallo donde se está mirando.
  ///
  /// El botón está en la barra de abajo y el mensaje al final de la lista: sin
  /// el aviso emergente, pulsar sin nada registrado parecía no hacer nada.
  void _fail(String message) {
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
  }

  Future<void> _confirm() async {
    if (_received.isEmpty) {
      _fail('Registra al menos un producto: '
          'es lo que entra al stock del puesto.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(shipmentServiceProvider).receiveShipment(
            shipmentId: widget.shipmentId,
            received: _received,
          );

      if (!mounted) return;
      ref.invalidate(shipmentDetailProvider(widget.shipmentId));
      ref.invalidate(shipmentItemsProvider(widget.shipmentId));
      Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipment = ref.watch(shipmentDetailProvider(widget.shipmentId));
    final items = ref.watch(shipmentItemsProvider(widget.shipmentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encomienda'),
        // En la PWA instalada no hay flecha del navegador: salir tiene que
        // estar a la vista.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: shipment.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'No se pudo cargar la encomienda',
          detail: e is AppException ? e.message : '$e',
          tone: EmptyTone.danger,
          onAction: () =>
              ref.invalidate(shipmentDetailProvider(widget.shipmentId)),
        ),
        data: (data) {
          if (data == null) {
            return const EmptyState(
              icon: Icons.help_outline,
              title: 'La encomienda no existe',
              detail: 'Puede que se haya anulado.',
            );
          }
          return items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el contenido',
              detail: e is AppException ? e.message : '$e',
              tone: EmptyTone.danger,
            ),
            data: (list) {
              if (data.isPending) _prefill(list);
              return _body(data, list);
            },
          );
        },
      ),
      bottomNavigationBar: shipment.value?.isPending ?? false
          ? BottomBar(
              child: BusyButton(
                label: 'Confirmar recepción',
                busy: _busy,
                onPressed: _confirm,
              ),
            )
          : null,
    );
  }

  Widget _body(Shipment shipment, List<ShipmentItem> items) {
    final theme = Theme.of(context);
    final pending = shipment.isPending;

    // En una a ciegas todo lo que se ve lo puso el vendedor ahora.
    final rows = [
      ...items,
      for (final product in _added.values)
        if (!items.any((i) => i.productId == product.id))
          ShipmentItem(
            id: 'nuevo-${product.id}',
            shipmentId: shipment.id,
            productId: product.id,
            productName: product.name,
            productImageUrl: product.imageUrl,
            productIcon: product.icon,
            price: product.price,
            priceConfirmed: product.priceConfirmed,
          ),
    ];

    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _Header(shipment: shipment),

          if (shipment.blind && pending)
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Text(
                'Este paquete llegó sin detalle. Abre la caja y registra lo '
                'que encuentres. Si un producto no está en el catálogo, '
                'créalo; el precio puedes dejarlo en blanco y preguntarlo '
                'después.',
                style: theme.textTheme.bodySmall,
              ),
            ),

          SectionHeader(
            label: pending ? 'Confirma lo que llegó' : 'Contenido',
            trailing: pending
                ? null
                : Text(
                    '${shipment.receivedTotal ?? 0} recibidas',
                    style: theme.textTheme.labelMedium,
                  ),
          ),

          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Text(
                pending
                    ? 'Todavía no has registrado nada.'
                    : 'La encomienda se cerró sin contenido.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final item in rows)
              _ItemRow(
                item: item,
                editable: pending && !_busy,
                // Una línea que despachó el administrador no se puede borrar:
                // si no llegó, la respuesta es 0 y eso queda como faltante.
                removable: item.sentQty == null,
                quantity: _received[item.productId],
                onChanged: (q) => _setQuantity(
                  item.productId,
                  q,
                  removable: item.sentQty == null,
                ),
              ),

          if (shipment.blind && pending) ...[
            const SizedBox(height: Space.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _addFromCatalog,
                icon: const Icon(Icons.add),
                label: const Text('Registrar un producto que llegó'),
              ),
            ),
          ],

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cabecera con el estado, quién la mandó y la nota.
class _Header extends StatelessWidget {
  const _Header({required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    final (color, label) = switch (shipment.status) {
      ShipmentStatus.enviado => (semantic.info, 'En camino'),
      ShipmentStatus.recibido when shipment.hasMissing => (
          semantic.danger,
          'Faltaron ${shipment.missingTotal}',
        ),
      ShipmentStatus.recibido => (semantic.positive, 'Recibida'),
      ShipmentStatus.anulado => (
          theme.colorScheme.onSurfaceVariant,
          'Anulada',
        ),
    };

    return Padding(
      padding: const EdgeInsets.all(Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(label: label, color: color),
              const SizedBox(width: Space.sm),
              if (shipment.blind)
                StatusPill(
                  label: 'Sin detallar',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            [
              if (shipment.standName != null) shipment.standName!,
              Fmt.dateTime(shipment.createdAt),
              if (shipment.createdByName != null)
                'envió ${shipment.createdByName}',
            ].join(' · '),
            style: theme.textTheme.labelSmall,
          ),
          if (shipment.receivedAt != null)
            Text(
              'Recibida ${Fmt.dateTime(shipment.receivedAt)}'
              '${shipment.receivedByName == null ? '' : ' por ${shipment.receivedByName}'}',
              style: theme.textTheme.labelSmall,
            ),
          if ((shipment.note ?? '').isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    const Icon(Icons.notes, size: 18),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(shipment.note!,
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Una línea: lo despachado, lo recibido y el faltante.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.editable,
    required this.removable,
    required this.quantity,
    required this.onChanged,
  });

  final ShipmentItem item;
  final bool editable;
  final bool removable;
  final int? quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = quantity ?? item.receivedQty ?? 0;
    final missing = item.sentQty == null ? 0 : item.sentQty! - current;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter, vertical: Space.sm),
      child: Row(
        children: [
          ProductAvatar(
            imageUrl: item.productImageUrl,
            productIcon: item.productIcon,
            categoryIcon: item.categoryIcon,
            size: 40,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName ?? 'Producto',
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (item.sentQty != null)
                      Text('Enviadas ${item.sentQty}',
                          style: theme.textTheme.labelSmall),
                    if (item.sentQty != null && missing > 0) ...[
                      const SizedBox(width: Space.sm),
                      Text(
                        'faltan $missing',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.semantic.danger),
                      ),
                    ],
                    // Un producto sin precio se vendería a 0. El vendedor
                    // tiene que saber que hay que preguntarlo.
                    if (!item.priceConfirmed) ...[
                      const SizedBox(width: Space.sm),
                      Text(
                        'precio por confirmar',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.semantic.warning),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (editable) ...[
            IconButton(
              onPressed: current <= 0 && !removable
                  ? null
                  : () => onChanged(current - 1),
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Una menos',
            ),
            SizedBox(
              width: 34,
              child: Text(
                '$current',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: () => onChanged(current + 1),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Una más',
            ),
          ] else
            Text(
              '${item.receivedQty ?? 0}',
              style: theme.textTheme.titleMedium,
            ),
        ],
      ),
    );
  }
}
