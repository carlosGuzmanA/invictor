import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/inventory_movement.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/movement_providers.dart';

/// Historial de movimientos del puesto activo (§10).
///
/// Es la vista de auditoría: cada fila es un evento inmutable. Los movimientos
/// no se editan ni se borran, así que aquí no hay acciones de escritura.
class MovementHistoryScreen extends ConsumerWidget {
  const MovementHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(movementHistoryProvider);
    final filter = ref.watch(movementFilterProvider);

    return Column(
      children: [
        _Filters(filter: filter),
        const Divider(height: 1),
        Expanded(
          child: history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el historial',
              detail: e is AppException ? e.message : '$e',
              tone: EmptyTone.danger,
              onAction: () => ref.invalidate(movementHistoryProvider),
            ),
            data: (movements) {
              if (movements.isEmpty) {
                return EmptyState(
                  icon: Icons.history,
                  title: 'Sin movimientos',
                  detail: filter.days == 0
                      ? 'Este puesto no tiene movimientos registrados.'
                      : 'Nada en los últimos ${filter.days} días. '
                          'Prueba a ampliar el período.',
                );
              }

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(movementHistoryProvider),
                child: ContentWidth(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: Space.xxl),
                    itemCount: movements.length,
                    itemBuilder: (context, i) {
                      final m = movements[i];
                      final showDate = i == 0 ||
                          !_sameDay(movements[i - 1].createdAt, m.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDate)
                            SectionHeader(label: _dayLabel(m.createdAt)),
                          _MovementRow(movement: m),
                          if (i < movements.length - 1 &&
                              _sameDay(m.createdAt, movements[i + 1].createdAt))
                            const Divider(height: 1, indent: 68),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime date) {
    final now = DateTime.now();
    if (_sameDay(date, now)) return 'Hoy';
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) return 'Ayer';
    return Fmt.date(date);
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.filter});

  final MovementFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(movementFilterProvider.notifier);
    final theme = Theme.of(context);

    return FilterRow(
      children: [
        for (final (days, label) in const [
          (1, 'Hoy'),
          (7, '7 días'),
          (30, '30 días'),
          (0, 'Todo'),
        ])
          ChoiceChip(
            label: Text(label),
            selected: filter.days == days,
            onSelected: (_) => notifier.setDays(days),
          ),
        Container(
          width: 1,
          margin: const EdgeInsets.symmetric(
              horizontal: Space.xs, vertical: Space.sm),
          color: theme.colorScheme.outlineVariant,
        ),
        ChoiceChip(
          label: const Text('Todos'),
          selected: filter.type == null,
          onSelected: (_) => notifier.setType(null),
        ),
        for (final t in MovementType.values)
          ChoiceChip(
            label: Text(t.label),
            selected: filter.type == t,
            onSelected: (_) => notifier.setType(t),
          ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final InventoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;
    final incoming = movement.type.isIncoming;
    final color = incoming ? semantic.positive : semantic.danger;

    final note = movement.note?.trim();
    final subtitle = [
      movement.type.label,
      Fmt.time(movement.createdAt),
      if (movement.profileName != null) movement.profileName!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter, vertical: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: incoming
                  ? semantic.positiveSurface
                  : semantic.dangerSurface,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(
              incoming ? Icons.south_west : Icons.north_east,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.productName ?? 'Producto eliminado',
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.labelSmall),
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          DeltaText(
            movement.effectiveQuantity,
            style: theme.textTheme.titleMedium,
            neutralWhenZero: false,
          ),
        ],
      ),
    );
  }
}
