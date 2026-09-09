import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/sales.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/dashboard_providers.dart';

/// Cuánto vende cada local en el período elegido.
///
/// «Actividad por puesto» ya mostraba stock y movimientos, que responden a
/// «cuánto hay» y «cuánto se movió». Esto responde a otra pregunta: **cuál
/// rinde**. Son cosas distintas — un puesto puede mover mucha mercadería en
/// traslados y vender poco.
class StandSalesSection extends ConsumerWidget {
  const StandSalesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(salesPeriodProvider);
    final sales = ref.watch(salesByStandProvider);
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
            title: 'No se pudieron cargar las ventas por local',
            detail: e is AppException ? e.message : '$e',
            tone: EmptyTone.danger,
            onAction: () => ref.invalidate(salesByStandProvider),
          ),
          data: (list) {
            final withSales = list.where((s) => s.units > 0).toList();

            if (withSales.isEmpty) {
              return EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Sin ventas en ${period.label.toLowerCase()}',
                detail: 'Cuando se registren salidas, aquí verás cuánto '
                    'vendió cada local y cómo se comparan entre sí.',
              );
            }

            // La barra de cada puesto se mide contra el que más vendió: en
            // una lista corta, comparar entre locales es la lectura útil, no
            // el valor absoluto.
            final top = withSales.first.amount;
            final totalAmount =
                withSales.fold<double>(0, (sum, s) => sum + s.amount);
            final totalUnits =
                withSales.fold<int>(0, (sum, s) => sum + s.units);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Space.gutter, Space.sm, Space.gutter, Space.md),
                  child: Text(
                    '${Fmt.money(totalAmount)} · ${Fmt.number(totalUnits)} '
                    'unidades en ${withSales.length} local(es)',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SectionHeader(label: 'Ventas por local'),
                for (final stand in withSales)
                  _StandSalesRow(
                    sales: stand,
                    share: totalAmount == 0 ? 0 : stand.amount / totalAmount,
                    relative: top == 0 ? 0 : stand.amount / top,
                  ),

                // Un puesto sin una sola venta en el período no es lo mismo
                // que uno que no existe: hay que poder verlo.
                if (list.length > withSales.length) ...[
                  const SectionHeader(label: 'Sin ventas en el período'),
                  for (final stand in list.where((s) => s.units == 0))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.storefront_outlined, size: 20),
                      title: Text(stand.standName),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// El mismo selector que la pestaña de ventas, para que cambiar de pestaña no
/// cambie el período que se está mirando.
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

class _StandSalesRow extends StatelessWidget {
  const _StandSalesRow({
    required this.sales,
    required this.share,
    required this.relative,
  });

  final StandSales sales;

  /// Qué parte del total factura este puesto.
  final double share;

  /// Cuánto factura comparado con el que más vende, de 0 a 1.
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
              Expanded(
                child: Text(
                  sales.standName,
                  style: theme.textTheme.titleSmall,
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
            ].join(' · '),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
