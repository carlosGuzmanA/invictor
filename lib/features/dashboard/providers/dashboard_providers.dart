import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/sales.dart';
import '../../../data/models/stand_summary.dart';
import '../../../services/service_providers.dart';

/// Indicadores por puesto. RLS decide cuáles: un encargado ve los suyos.
final standSummariesProvider =
    FutureProvider.autoDispose<List<StandSummary>>(
  (ref) => ref.watch(dashboardServiceProvider).fetchStandSummaries(),
);

final stockAlertsProvider = FutureProvider.autoDispose<List<StockAlert>>(
  (ref) => ref.watch(dashboardServiceProvider).fetchStockAlerts(),
);

final differencesProvider =
    FutureProvider.autoDispose<List<InventoryDifference>>(
  (ref) => ref.watch(dashboardServiceProvider).fetchDifferences(),
);

/// Totales del negocio, sumando los puestos accesibles.
class DashboardTotals {
  const DashboardTotals({
    required this.exitsToday,
    required this.exitsWeek,
    required this.unitsTotal,
    required this.alerts,
    required this.negatives,
    required this.openInventories,
    required this.stands,
  });

  final int exitsToday;
  final int exitsWeek;
  final int unitsTotal;
  final int alerts;
  final int negatives;
  final int openInventories;
  final int stands;

  factory DashboardTotals.from(List<StandSummary> list) => DashboardTotals(
        exitsToday: list.fold(0, (s, e) => s + e.exitsToday),
        exitsWeek: list.fold(0, (s, e) => s + e.exitsWeek),
        unitsTotal: list.fold(0, (s, e) => s + e.unitsTotal),
        alerts: list.fold(0, (s, e) => s + e.productsLow),
        negatives: list.fold(0, (s, e) => s + e.productsNegative),
        openInventories: list.fold(0, (s, e) => s + e.openInventories),
        stands: list.length,
      );
}

final dashboardTotalsProvider = Provider.autoDispose<DashboardTotals?>((ref) {
  final summaries = ref.watch(standSummariesProvider).value;
  if (summaries == null) return null;
  return DashboardTotals.from(summaries);
});

// ============================================================== Ventas

/// Período de análisis. Los nombres importan: el administrador piensa en
/// "esta semana", no en "los últimos 7 días".
enum SalesPeriod {
  today(1, 'Hoy', 'ayer'),
  week(7, '7 días', 'los 7 anteriores'),
  month(30, '30 días', 'los 30 anteriores'),
  quarter(90, '90 días', 'los 90 anteriores');

  const SalesPeriod(this.days, this.label, this.previousLabel);

  final int days;
  final String label;

  /// Con qué se compara, para escribirlo en la pantalla sin ambigüedad.
  final String previousLabel;
}

class SalesPeriodNotifier extends Notifier<SalesPeriod> {
  /// Hoy, no la semana. Lo primero que se pregunta un administrador al abrir
  /// el dashboard es cuánto se vendió hoy; el resto de rangos está a un toque.
  @override
  SalesPeriod build() => SalesPeriod.today;

  void select(SalesPeriod period) => state = period;
}

final salesPeriodProvider =
    NotifierProvider<SalesPeriodNotifier, SalesPeriod>(
        SalesPeriodNotifier.new);

final salesSummaryProvider = FutureProvider.autoDispose<SalesSummary>((ref) {
  final period = ref.watch(salesPeriodProvider);
  return ref
      .watch(dashboardServiceProvider)
      .fetchSalesSummary(days: period.days);
});

/// Serie diaria para el gráfico. Siempre 14 días: con menos no se aprecia la
/// tendencia y con más las barras quedan ilegibles en un móvil.
final dailySalesProvider = FutureProvider.autoDispose<List<DailySales>>(
  (ref) => ref.watch(dashboardServiceProvider).fetchDailySales(days: 14),
);

final productSalesProvider =
    FutureProvider.autoDispose<List<ProductSales>>((ref) {
  final period = ref.watch(salesPeriodProvider);
  return ref
      .watch(dashboardServiceProvider)
      .fetchProductSales(days: period.days);
});

/// Los más vendidos del período.
final topSellersProvider = Provider.autoDispose<List<ProductSales>>((ref) {
  final all = ref.watch(productSalesProvider).value ?? const [];
  final sold = all.where((p) => p.units > 0).toList()
    ..sort((a, b) => b.units.compareTo(a.units));
  return sold.take(8).toList();
});

/// Cuántos días hacen falta sin vender para considerar un producto parado.
///
/// No depende del período elegido. Con el selector en «Hoy» —que es lo
/// habitual— cualquier producto que no se haya vendido esta mañana saldría
/// como estancado, y eso es casi el catálogo entero: la lista dejaría de
/// señalar nada.
const stagnantWindowDays = 30;

/// Ventas del último mes, solo para decidir qué está parado.
final _stagnantSourceProvider =
    FutureProvider.autoDispose<List<ProductSales>>((ref) {
  return ref
      .watch(dashboardServiceProvider)
      .fetchProductSales(days: stagnantWindowDays);
});

/// Productos parados: un mes sin venderse y con stock encima.
///
/// No es "el menos vendido" sino capital inmovilizado, que es lo que sirve
/// para decidir qué retirar del puesto. Se ordena por stock: cuanto más hay
/// parado, más urge moverlo.
final stagnantProductsProvider =
    Provider.autoDispose<List<ProductSales>>((ref) {
  final all = ref.watch(_stagnantSourceProvider).value ?? const [];
  final stagnant = all.where((p) => p.isStagnant).toList()
    ..sort((a, b) => b.stockNow.compareTo(a.stockNow));
  return stagnant.take(8).toList();
});

final monthlySalesProvider = FutureProvider.autoDispose<List<MonthlySales>>(
  (ref) => ref.watch(dashboardServiceProvider).fetchMonthlySales(),
);

/// Ventas por vendedor en el período elegido, de mayor a menor facturación.
final salesBySellerProvider =
    FutureProvider.autoDispose<List<SellerSales>>((ref) {
  final period = ref.watch(salesPeriodProvider);
  return ref
      .watch(dashboardServiceProvider)
      .fetchSalesBySeller(days: period.days);
});

/// Ventas por puesto en el período elegido, de mayor a menor facturación.
final salesByStandProvider =
    FutureProvider.autoDispose<List<StandSales>>((ref) {
  final period = ref.watch(salesPeriodProvider);
  return ref
      .watch(dashboardServiceProvider)
      .fetchSalesByStand(days: period.days);
});
