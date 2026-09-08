import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/models/product.dart';
import '../../../data/models/shipment_item.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../../admin/providers/admin_providers.dart';
import '../../products/providers/product_providers.dart';

/// Despachar mercadería a un puesto. Solo staff, y RLS lo aplica.
///
/// Dos caminos según cuánto se sepa al despachar:
///
/// - **Detallada:** se listan los productos y sus cantidades. El vendedor solo
///   confirma qué llegó, y el sistema calcula el faltante.
/// - **A ciegas:** se declara que se mandó un paquete y nada más. Es el caso
///   real más común —se compra a última hora y se despacha sin apuntar— y el
///   contenido lo registra el vendedor al abrirlo.
class DispatchShipmentScreen extends ConsumerStatefulWidget {
  const DispatchShipmentScreen({super.key});

  @override
  ConsumerState<DispatchShipmentScreen> createState() =>
      _DispatchShipmentScreenState();
}

class _DispatchShipmentScreenState
    extends ConsumerState<DispatchShipmentScreen> {
  String? _standId;
  bool _blind = false;
  final _noteCtrl = TextEditingController();

  /// productId -> cantidad despachada.
  final Map<String, int> _quantities = {};

  /// Los productos elegidos, para pintarlos sin volver a consultar.
  final Map<String, Product> _chosen = {};

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _totalUnits =>
      _quantities.values.fold(0, (sum, qty) => sum + qty);

  Future<void> _addProducts() async {
    final picked = await _ProductPickerSheet.show(
      context,
      alreadyChosen: _quantities.keys.toSet(),
    );
    if (picked == null || picked.isEmpty) return;

    setState(() {
      for (final product in picked) {
        _chosen[product.id] = product;
        // Se añade con 1 y se ajusta en la lista: es más rápido que pedir la
        // cantidad en un diálogo por cada producto.
        _quantities[product.id] = _quantities[product.id] ?? 1;
      }
    });
  }

  void _setQuantity(String productId, int quantity) {
    setState(() {
      if (quantity <= 0) {
        _quantities.remove(productId);
        _chosen.remove(productId);
      } else {
        _quantities[productId] = quantity;
      }
    });
  }

  /// Muestra el fallo donde se está mirando.
  ///
  /// El mensaje vivía al final de la lista y el botón está en la barra de
  /// abajo: al pulsar sin haber elegido el puesto, el aviso aparecía fuera de
  /// la pantalla y el botón parecía no hacer nada.
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

  Future<void> _dispatch() async {
    final standId = _standId;
    if (standId == null) {
      _fail('Elige el puesto de destino.');
      return;
    }
    if (!_blind && _quantities.isEmpty) {
      _fail('Añade al menos un producto, o marca «No detallar el contenido» '
          'si todavía no sabes qué mandas.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(shipmentServiceProvider).createShipment(
            toStandId: standId,
            blind: _blind,
            note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
            // En una encomienda a ciegas no se envían líneas aunque se hayan
            // elegido productos: el contenido lo descubre el vendedor, y
            // mandar ambas cosas dejaría dos versiones de la verdad.
            items: _blind
                ? const []
                : [
                    for (final entry in _quantities.entries)
                      ShipmentItem(
                        id: '',
                        shipmentId: '',
                        productId: entry.key,
                        sentQty: entry.value,
                      ),
                  ],
          );

      if (!mounted) return;
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
    final theme = Theme.of(context);
    final stands = ref.watch(allStandsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Despachar encomienda'),
        // Explícito y no automático: en la PWA instalada no hay barra del
        // navegador con su flecha, así que salir tiene que estar a la vista.
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancelar',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.lg, Space.gutter, 120),
          children: [
            stands.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                'No se pudieron cargar los puestos',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
              data: (list) {
                final destinations =
                    list.where((s) => !s.isWarehouse).toList();
                return DropdownButtonFormField<String>(
                  initialValue: _standId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '¿A qué puesto lo envías?',
                    prefixIcon: Icon(Icons.storefront),
                  ),
                  items: [
                    for (final stand in destinations)
                      DropdownMenuItem(
                        value: stand.id,
                        child: Text(stand.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged:
                      _busy ? null : (v) => setState(() => _standId = v),
                );
              },
            ),
            const SizedBox(height: Space.lg),

            Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                value: _blind,
                onChanged: _busy ? null : (v) => setState(() => _blind = v),
                title: const Text('No detallar el contenido'),
                subtitle: Text(
                  _blind
                      ? 'El vendedor registrará qué llegó, con foto y cantidad. '
                          'Tendrás que decirle los precios.'
                      : 'Vas a listar los productos y sus cantidades.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),

            if (!_blind) ...[
              const SizedBox(height: Space.lg),
              SectionHeader(
                label: 'Contenido',
                trailing: _totalUnits == 0
                    ? null
                    : Text('$_totalUnits unidades',
                        style: theme.textTheme.labelMedium),
              ),
              if (_quantities.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.md),
                  child: Text(
                    'Todavía no has añadido productos.',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                for (final entry in _quantities.entries)
                  _DispatchRow(
                    product: _chosen[entry.key],
                    quantity: entry.value,
                    enabled: !_busy,
                    onChanged: (q) => _setQuantity(entry.key, q),
                  ),
              const SizedBox(height: Space.sm),
              OutlinedButton.icon(
                onPressed: _busy ? null : _addProducts,
                icon: const Icon(Icons.add),
                label: const Text('Añadir productos'),
              ),
            ],

            const SizedBox(height: Space.lg),
            TextField(
              controller: _noteCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nota para el vendedor (opcional)',
                hintText: 'Por ejemplo: "las tazas van en la caja chica"',
                prefixIcon: Icon(Icons.notes),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: Space.md),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomBar(
        child: BusyButton(
          // Sin nada añadido, «Despachar 0 unidades» invita a pulsar algo que
          // va a fallar. El texto dice lo que falta.
          label: switch ((_blind, _totalUnits)) {
            (true, _) => 'Despachar paquete',
            (false, 0) => 'Añade productos para despachar',
            (false, final units) => 'Despachar $units unidades',
          },
          busy: _busy,
          onPressed: _dispatch,
        ),
      ),
    );
  }
}

/// Una línea del contenido, con la cantidad ajustable.
class _DispatchRow extends StatelessWidget {
  const _DispatchRow({
    required this.product,
    required this.quantity,
    required this.enabled,
    required this.onChanged,
  });

  final Product? product;
  final int quantity;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          ProductAvatar(
            imageUrl: product?.imageUrl,
            productIcon: product?.icon,
            size: 36,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              product?.name ?? 'Producto',
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: enabled ? () => onChanged(quantity - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Quitar una',
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            onPressed: enabled ? () => onChanged(quantity + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Añadir una',
          ),
        ],
      ),
    );
  }
}

/// Selector del catálogo global, con búsqueda y selección múltiple.
class _ProductPickerSheet extends ConsumerStatefulWidget {
  const _ProductPickerSheet({required this.alreadyChosen});

  final Set<String> alreadyChosen;

  static Future<List<Product>?> show(
    BuildContext context, {
    required Set<String> alreadyChosen,
  }) {
    return showModalBottomSheet<List<Product>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPickerSheet(alreadyChosen: alreadyChosen),
    );
  }

  @override
  ConsumerState<_ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<_ProductPickerSheet> {
  final _searchCtrl = TextEditingController();
  final Set<String> _selected = {};
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Space.gutter,
          right: Space.gutter,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: false,
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Buscar producto',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: Space.sm),
            Flexible(
              child: products.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.xl),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text(e is AppException ? e.message : '$e'),
                ),
                data: (list) {
                  final visible = list
                      .where((p) =>
                          _search.isEmpty ||
                          p.name.toLowerCase().contains(_search) ||
                          (p.sku ?? '').toLowerCase().contains(_search))
                      .toList();

                  if (visible.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(Space.xl),
                      child: Text('Ningún producto coincide.'),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final product = visible[i];
                      final chosen = _selected.contains(product.id) ||
                          widget.alreadyChosen.contains(product.id);

                      return CheckboxListTile(
                        value: chosen,
                        // Un producto ya añadido no se puede quitar desde
                        // aquí: se ajusta su cantidad en la lista de atrás.
                        onChanged: widget.alreadyChosen.contains(product.id)
                            ? null
                            : (on) => setState(() {
                                  if (on ?? false) {
                                    _selected.add(product.id);
                                  } else {
                                    _selected.remove(product.id);
                                  }
                                }),
                        secondary: ProductAvatar(
                          imageUrl: product.imageUrl,
                          productIcon: product.icon,
                          size: 36,
                        ),
                        title: Text(product.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: product.sku == null
                            ? null
                            : Text(product.sku!,
                                style: Theme.of(context).textTheme.labelSmall),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: Space.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () {
                        final all = products.value ?? const <Product>[];
                        Navigator.of(context).pop(
                          all.where((p) => _selected.contains(p.id)).toList(),
                        );
                      },
                child: Text(
                  _selected.isEmpty
                      ? 'Elige productos'
                      : 'Añadir ${_selected.length}',
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
  }
}
