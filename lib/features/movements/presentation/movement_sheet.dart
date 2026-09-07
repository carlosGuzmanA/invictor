import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/models/stand_catalog_item.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Movimiento que se acaba de registrar, para que quien llame pueda reflejar
/// el cambio en pantalla sin releer del servidor.
class RegisteredMovement {
  const RegisteredMovement({required this.type, required this.quantity});

  final MovementType type;
  final int quantity;

  /// Cantidad con signo: lo que hay que sumar al stock mostrado.
  int get delta => quantity * type.sign;
}

/// Hoja para registrar un movimiento sobre un producto de un puesto.
///
/// Dos toques para el caso habitual —tocar el producto y confirmar— con la
/// salida preseleccionada, que es el 95 % del uso (§4.1). No se registra con un
/// solo toque a propósito: el stock es dinero y un roce accidental no debe
/// descontar mercadería; corregirlo obliga a un movimiento compensatorio, que
/// cuesta más que confirmar.
///
/// Los tipos disponibles dependen del rol. Un vendedor no ve los ajustes, y
/// tampoco podría insertarlos: lo impide la policy `movements_insert`
/// (migración 0003). La interfaz solo evita el intento fallido.
class MovementSheet extends ConsumerStatefulWidget {
  const MovementSheet({
    super.key,
    required this.item,
    required this.standId,
    this.type = MovementType.salida,
  });

  final StandCatalogItem item;
  final String standId;
  final MovementType type;

  /// Devuelve el movimiento registrado, o null si se canceló.
  static Future<RegisteredMovement?> show(
    BuildContext context, {
    required StandCatalogItem item,
    required String standId,
    MovementType type = MovementType.salida,
  }) {
    return showModalBottomSheet<RegisteredMovement>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MovementSheet(item: item, standId: standId, type: type),
    );
  }

  @override
  ConsumerState<MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends ConsumerState<MovementSheet> {
  late MovementType _type = widget.type;
  int _quantity = 1;
  bool _busy = false;
  String? _error;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _resulting => widget.item.quantity + (_quantity * _type.sign);

  void _bump(int delta) {
    final next = _quantity + delta;
    if (next < 1) return;
    HapticFeedback.selectionClick();
    setState(() => _quantity = next);
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(movementServiceProvider).registerMovement(
            productId: widget.item.productId,
            standId: widget.standId,
            type: _type,
            quantity: _quantity,
            note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop(
          RegisteredMovement(type: _type, quantity: _quantity),
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  /// Un vendedor solo registra movimientos operativos; los ajustes y traslados
  /// son de encargado/admin, y RLS lo aplica de verdad.
  List<MovementType> _availableTypes(bool isStaff) {
    if (!isStaff) return MovementType.operationalTypes;
    return const [
      MovementType.salida,
      MovementType.entrada,
      MovementType.devolucion,
      MovementType.ajustePositivo,
      MovementType.ajusteNegativo,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final isStaff = ref.watch(currentProfileProvider).value?.isStaff ?? false;
    final types = _availableTypes(isStaff);

    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.productName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              [
                if (item.sku != null) item.sku!,
                'stock actual: ${item.quantity}',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),

            // Tipo de movimiento. Salida viene preseleccionada.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in types)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(t.label),
                        selected: _type == t,
                        avatar: Icon(
                          t.isIncoming ? Icons.south_west : Icons.north_east,
                          size: 16,
                        ),
                        onSelected:
                            _busy ? null : (_) => setState(() => _type = t),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Contador grande: se opera de pie y con una mano.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundButton(
                  icon: Icons.remove,
                  onPressed: _quantity > 1 && !_busy ? () => _bump(-1) : null,
                ),
                Column(
                  children: [
                    Text(
                      '$_quantity',
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text('unidades', style: theme.textTheme.bodySmall),
                  ],
                ),
                _RoundButton(
                  icon: Icons.add,
                  onPressed: _busy ? null : () => _bump(1),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Antes/después: el efecto se ve antes de confirmar.
            Container(
              padding: const EdgeInsets.symmetric(
                  vertical: Space.md, horizontal: Space.lg),
              decoration: BoxDecoration(
                color: _resulting < 0
                    ? theme.semantic.dangerSurface
                    : theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${item.quantity}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    child: Icon(Icons.arrow_forward,
                        size: 16, color: theme.colorScheme.outline),
                  ),
                  Text(
                    '$_resulting',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: _resulting < 0 ? theme.semantic.danger : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),

            if (_resulting < 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: theme.semantic.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El stock quedará negativo. Se registra igual, pero '
                      'conviene revisar por qué el sistema no conocía esas unidades.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.semantic.danger),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _type == MovementType.ajustePositivo ||
                        _type == MovementType.ajusteNegativo
                    ? 'Motivo del ajuste (recomendado)'
                    : 'Observación (opcional)',
                prefixIcon: const Icon(Icons.notes),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],

            const SizedBox(height: 20),
            BusyButton(
              label: 'Registrar ${_type.label.toLowerCase()}',
              busy: _busy,
              onPressed: _confirm,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      iconSize: 28,
      style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
      icon: Icon(icon),
    );
  }
}
