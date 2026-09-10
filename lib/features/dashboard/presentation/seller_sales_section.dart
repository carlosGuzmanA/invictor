import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/sales.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/dashboard_providers.dart';

/// Quién vendió cuánto en el período elegido.
///
/// El dato estaba desde el primer día —cada movimiento guarda quién lo
/// registró— pero no se enseñaba en ninguna parte. Con varios vendedores
/// repartidos entre locales, es la pregunta que faltaba para saber a quién
/// reconocer y con quién sentarse.
class SellerSalesSection extends ConsumerWidget {
  const SellerSalesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(salesPeriodProvider);
    final sales = ref.watch(salesBySellerProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: [
        const _PeriodSelector(),
        sales.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar las ventas por vendedor',
            detail: e is AppException ? e.message : '$e',
            tone: EmptyTone.danger,
            onAction: () => ref.invalidate(salesBySellerProvider),
          ),
          data: (list) {
            final selling = list.where((s) => s.units != 0).toList();

            if (selling.isEmpty) {
              return EmptyState(
                icon: Icons.people_outline,
                title: 'Sin ventas en ${period.label.toLowerCase()}',
                detail: 'Cuando se registren salidas, aquí verás quién las '
                    'hizo y cuánto vendió cada uno.',
              );
            }

            // Cada barra se mide contra quien más vendió: comparar entre
            // personas es la lectura útil, no el valor absoluto.
            final top = selling.first.amount;
            final total = selling.fold<double>(0, (sum, s) => sum + s.amount);
            final units = selling.fold<int>(0, (sum, s) => sum + s.units);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Space.gutter, Space.sm, Space.gutter, Space.md),
                  child: Text(
                    '${Fmt.money(total)} · ${Fmt.number(units)} unidades '
                    'entre ${selling.length} persona(s)',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SectionHeader(label: 'Ventas por vendedor'),
                for (final seller in selling)
                  _SellerRow(
                    sales: seller,
                    share: total == 0 ? 0 : seller.amount / total,
                    relative: top == 0 ? 0 : seller.amount / top,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// El mismo selector que el resto del dashboard: cambiar de pestaña no debe
/// cambiar el período que se está mirando.
class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(salesPeriodProvider);

    return FilterRow(
      children: [
        for (final p in SalesPeriod.values)
          ChoiceChip(
            label: Text(p.label),
            selected: p == current,
            onSelected: (_) =>
                ref.read(salesPeriodProvider.notifier).select(p),
          ),
      ],
    );
  }
}

class _SellerRow extends StatelessWidget {
  const _SellerRow({
    required this.sales,
    required this.share,
    required this.relative,
  });

  final SellerSales sales;
  final double share;
  final double relative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter, vertical: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                child: Text(
                  _initials(sales.displayName),
                  style: theme.textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  sales.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontStyle:
                        sales.isUnattributed ? FontStyle.italic : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                Fmt.money(sales.amount),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(
              value: relative.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            [
              '${Fmt.number(sales.units)} unidades',
              '${(share * 100).round()} % del total',
              'ticket ${Fmt.money(sales.averageTicket)}',
              if (sales.stands.isNotEmpty) sales.stands.join(', '),
            ].join(' · '),
            style: theme.textTheme.labelSmall,
          ),
          // Los ajustes que genera el cierre de inventario no tienen autor
          // humano. Decirlo evita que parezca un vendedor fantasma.
          if (sales.isUnattributed)
            Text(
              'Movimientos sin autor, como los ajustes del cierre de inventario.',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }

  /// Iniciales para el avatar; sirve igual con un nombre o con un correo.
  static String _initials(String name) {
    final parts = name
        .split(RegExp(r'[\s@._]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }
}
