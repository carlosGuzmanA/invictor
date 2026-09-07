import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/sales.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../providers/dashboard_providers.dart';

/// Ventas estimadas, ranking y rotación.
///
/// «Estimadas» va en la pantalla, no solo en el código: el sistema registra
/// salidas, no pagos (§1). Un descuento no se refleja y una rotura cuenta como
/// salida. Presentarlo como facturación llevaría a decisiones sobre un número
/// que no es el que entra en caja.
class SalesSection extends ConsumerWidget {
  const SalesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(salesPeriodProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(label: 'Ventas estimadas'),
        _PeriodSelector(selected: period),
        _SummaryCard(period: period),
        const _DailyChart(),
        const _TopSellers(),
        const _Stagnant(),
      ],
    );
  }
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector({required this.selected});

  final SalesPeriod selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilterRow(
      children: [
        for (final p in SalesPeriod.values)
          ChoiceChip(
            label: Text(p.label),
            selected: p == selected,
            onSelected: (_) =>
                ref.read(salesPeriodProvider.notifier).select(p),
          ),
      ],
    );
  }
}

/// La cifra principal, con su comparación. Un importe suelto no dice nada:
/// «$340.000» solo significa algo junto a «un 18 % más que la semana pasada».
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.period});

  final SalesPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(salesSummaryProvider);
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: summary.when(
            loading: () => const SizedBox(
              height: 92,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SizedBox(
              height: 92,
              child: Center(
                child: Text('No se pudieron calcular las ventas',
                    style: theme.textTheme.bodySmall),
              ),
            ),
            data: (s) {
              final change = s.amountChange;
              final up = (change ?? 0) >= 0;
              final changeColor =
                  up ? semantic.positive : semantic.danger;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(period.label.toUpperCase(),
                      style: theme.textTheme.labelSmall),
                  const SizedBox(height: Space.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          Fmt.money(s.amount),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ),
                      if (change != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm, vertical: Space.xs),
                          decoration: BoxDecoration(
                            color: changeColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                up
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                size: 14,
                                color: changeColor,
                              ),
                              const SizedBox(width: Space.xs),
                              Text(
                                '${up ? '+' : ''}'
                                '${(change * 100).round()} %',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: changeColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    change == null
                        ? 'Sin ventas en ${period.previousLabel} para comparar'
                        : 'frente a ${Fmt.money(s.prevAmount)} '
                            'en ${period.previousLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.md),
                  const Divider(height: 1),
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      _Mini(
                          value: Fmt.number(s.units), label: 'unidades'),
                      _Mini(
                          value: Fmt.number(s.products),
                          label: 'productos'),
                      _Mini(
                        value: Fmt.money(s.averageTicket),
                        label: 'precio medio',
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Barras de los últimos 14 días, dibujadas con widgets.
///
/// Sin librería de gráficos a propósito: añadiría cientos de KB al bundle de
/// una PWA que ya pesa, y para «cuánto se vendió cada día» catorce barras y
/// una etiqueta bastan.
class _DailyChart extends ConsumerWidget {
  const _DailyChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailySalesProvider);
    final theme = Theme.of(context);

    return daily.when(
      loading: () => const SizedBox(height: 140),
      error: (e, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text('Sin ventas registradas todavía.',
                style: theme.textTheme.bodySmall),
          );
        }

        // Rellena los días sin ventas: un hueco en la serie haría creer que
        // no hubo datos, cuando lo que hubo fue cero.
        final byDay = {
          for (final d in list)
            DateTime(d.date.year, d.date.month, d.date.day): d,
        };
        final today = DateTime.now();
        final days = [
          for (var i = 13; i >= 0; i--)
            DateTime(today.year, today.month, today.day)
                .subtract(Duration(days: i)),
        ];

        final maxAmount = byDay.values
            .map((d) => d.amount)
            .fold<double>(0, (a, b) => a > b ? a : b);

        return Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.md, Space.md, Space.md, Space.sm),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ÚLTIMOS 14 DÍAS',
                      style: theme.textTheme.labelSmall),
                  const SizedBox(height: Space.md),
                  SizedBox(
                    height: 96,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final day in days)
                          Expanded(
                            child: _Bar(
                              amount: byDay[day]?.amount ?? 0,
                              units: byDay[day]?.units ?? 0,
                              max: maxAmount,
                              date: day,
                              isToday: day.day == today.day &&
                                  day.month == today.month,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(Fmt.date(days.first),
                          style: theme.textTheme.labelSmall),
                      Text('máx. ${Fmt.money(maxAmount)}',
                          style: theme.textTheme.labelSmall),
                      Text('hoy', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.amount,
    required this.units,
    required this.max,
    required this.date,
    required this.isToday,
  });

  final double amount;
  final int units;
  final double max;
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Mínimo de 3 px para que un día con cero se distinga de un hueco.
    final ratio = max <= 0 ? 0.0 : amount / max;
    final height = amount <= 0 ? 3.0 : (ratio * 84).clamp(6.0, 84.0);

    return Tooltip(
      message: '${Fmt.date(date)}\n'
          '${Fmt.money(amount)} · ${Fmt.number(units)} unidades',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: height,
              decoration: BoxDecoration(
                color: amount <= 0
                    ? theme.colorScheme.outlineVariant
                    : isToday
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primary.withValues(alpha: 0.45),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopSellers extends ConsumerWidget {
  const _TopSellers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(topSellersProvider);
    final loading = ref.watch(productSalesProvider).isLoading;
    final theme = Theme.of(context);

    if (loading && top.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(Space.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (top.isEmpty) {
      return Column(
        children: [
          const SectionHeader(label: 'Más vendidos'),
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text('Sin ventas en el período elegido.',
                style: theme.textTheme.bodySmall),
          ),
        ],
      );
    }

    final maxUnits = top.first.units;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(label: 'Más vendidos'),
        for (final p in top)
          _RankRow(product: p, ratio: maxUnits == 0 ? 0 : p.units / maxUnits),
      ],
    );
  }
}

/// Fila del ranking con barra de proporción: se lee de un vistazo cuál manda,
/// sin comparar cifras mentalmente.
class _RankRow extends StatelessWidget {
  const _RankRow({required this.product, required this.ratio});

  final ProductSales product;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter, vertical: Space.sm),
      child: Row(
        children: [
          ProductAvatar(
            imageUrl: product.imageUrl,
            productIcon: product.productIcon,
            categoryIcon: product.categoryIcon,
            size: Sizes.thumb,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.productName,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${Fmt.number(product.units)} u.',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(Fmt.money(product.amount),
                  style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// Productos parados con stock encima.
///
/// No es «el menos vendido»: es capital inmovilizado. Ordenado por cantidad,
/// porque lo que urge mover es lo que más ocupa.
class _Stagnant extends ConsumerWidget {
  const _Stagnant();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stagnant = ref.watch(stagnantProductsProvider);
    final period = ref.watch(salesPeriodProvider);
    final theme = Theme.of(context);

    if (ref.watch(productSalesProvider).isLoading) {
      return const SizedBox.shrink();
    }
    if (stagnant.isEmpty) {
      return Column(
        children: [
          const SectionHeader(label: 'Sin movimiento'),
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Row(
              children: [
                Icon(Icons.verified,
                    size: Sizes.icon, color: theme.semantic.positive),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text('Todo el stock tuvo movimiento en el período.',
                      style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: 'Sin movimiento en ${period.label.toLowerCase()}',
          trailing:
              Text('${stagnant.length}', style: theme.textTheme.labelSmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, Space.sm, Space.gutter, 0),
          child: Text(
            'Con existencias y sin ventas: es stock inmovilizado.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (final p in stagnant) _StagnantRow(product: p),
      ],
    );
  }
}

class _StagnantRow extends StatelessWidget {
  const _StagnantRow({required this.product});

  final ProductSales product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: ProductAvatar(
        imageUrl: product.imageUrl,
        productIcon: product.productIcon,
        categoryIcon: product.categoryIcon,
        size: Sizes.thumb,
      ),
      title: Text(product.productName,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        product.neverSold
            ? 'nunca se ha vendido'
            : 'última venta hace ${product.daysSinceSale} días',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Fmt.number(product.stockNow),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.semantic.warning,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text('en stock', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
