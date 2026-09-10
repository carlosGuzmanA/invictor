import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_exception.dart';
import '../data/models/sales.dart';
import '../data/models/stand_summary.dart';
import 'supabase_service.dart';

/// Indicadores del dashboard (§10).
///
/// Todo se agrega en la base, no en Dart: traer los movimientos del mes para
/// sumarlos en el cliente serían miles de filas por cada apertura de pantalla.
/// Las vistas respetan RLS, así que un encargado ve sus puestos y un admin todos.
class DashboardService {
  const DashboardService();

  static const _standSummary = 'v_stand_summary';
  static const _stockAlerts = 'v_stock_alerts';
  static const _differences = 'v_inventory_differences';
  static const _salesDaily = 'v_sales_daily';
  static const _salesMonthly = 'v_sales_monthly';

  SupabaseClient get _db => SupabaseService.client;

  Future<List<StandSummary>> fetchStandSummaries({
    bool onlyActive = true,
  }) async {
    try {
      var query = _db.from(_standSummary).select();
      if (onlyActive) query = query.eq('active', true);
      final rows = await query.order('stand_name');
      return rows.map<StandSummary>((r) => StandSummary.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<List<StockAlert>> fetchStockAlerts({String? standId}) async {
    try {
      var query = _db.from(_stockAlerts).select();
      if (standId != null) query = query.eq('stand_id', standId);
      // Los negativos primero: 'negativo' < 'bajo' alfabéticamente.
      final rows = await query.order('severity').order('quantity');
      return rows.map<StockAlert>((r) => StockAlert.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  // ------------------------------------------------------ Ventas estimadas
  //
  // "Estimadas" no es un matiz: el sistema registra salidas, no pagos (§1).
  // Un descuento no se refleja y una rotura cuenta como salida. Sirve para
  // comparar temporadas y ordenar por rotación, no para cuadrar caja.

  /// Totales del período y del anterior de la misma duración.
  Future<SalesSummary> fetchSalesSummary({
    int days = 1,
    String? standId,
  }) async {
    try {
      final rows = await _db.rpc(
        'sales_summary',
        params: {'p_days': days, 'p_stand_id': standId},
      ) as List<dynamic>;
      if (rows.isEmpty) return SalesSummary.empty;
      return SalesSummary.fromMap(rows.first as Map<String, dynamic>);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Ventas día a día, para el gráfico. Agrupa los puestos accesibles.
  Future<List<DailySales>> fetchDailySales({
    int days = 14,
    String? standId,
  }) async {
    try {
      final from = DateTime.now().subtract(Duration(days: days - 1));
      var query = _db.from(_salesDaily).select();
      if (standId != null) query = query.eq('stand_id', standId);
      final rows = await query
          .gte('sale_date', _isoDate(from))
          .order('sale_date');

      // La vista devuelve una fila por día Y puesto: se suman por día.
      final byDate = <String, DailySales>{};
      for (final row in rows) {
        final item = DailySales.fromMap(row);
        final key = _isoDate(item.date);
        final prev = byDate[key];
        byDate[key] = prev == null
            ? item
            : DailySales(
                date: item.date,
                units: prev.units + item.units,
                amount: prev.amount + item.amount,
              );
      }
      return byDate.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Ventas agrupadas por puesto en los últimos [days] días.
  ///
  /// `v_sales_daily` ya viene desglosada por día **y** puesto, así que aquí
  /// solo se suman los días de cada puesto. Se hace en Dart y no en la base
  /// porque son unas pocas decenas de filas —un puñado de puestos por un mes—
  /// y añadir otra vista por esto no compensa.
  Future<List<StandSales>> fetchSalesByStand({int days = 1}) async {
    try {
      final from = DateTime.now().subtract(Duration(days: days - 1));
      final rows = await _db
          .from(_salesDaily)
          .select()
          .gte('sale_date', _isoDate(from));

      final byStand = <String, StandSales>{};
      for (final row in rows) {
        final item = StandSales.fromMap(row);
        final prev = byStand[item.standId];
        byStand[item.standId] = prev == null
            ? item
            : StandSales(
                standId: item.standId,
                standName: item.standName,
                units: prev.units + item.units,
                amount: prev.amount + item.amount,
              );
      }

      // De mayor a menor facturación: la pregunta que se hace mirando esto es
      // cuál rinde y cuál no.
      return byStand.values.toList()
        ..sort((a, b) => b.amount.compareTo(a.amount));
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Ranking de productos. Incluye los que vendieron cero, para poder ver
  /// qué lleva tiempo parado con stock encima.
  Future<List<ProductSales>> fetchProductSales({
    int days = 1,
    String? standId,
  }) async {
    try {
      final rows = await _db.rpc(
        'product_sales',
        params: {'p_days': days, 'p_stand_id': standId},
      ) as List<dynamic>;
      return rows
          .map((r) => ProductSales.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Ventas por mes, para comparar temporadas entre años.
  Future<List<MonthlySales>> fetchMonthlySales({String? standId}) async {
    try {
      var query = _db.from(_salesMonthly).select();
      if (standId != null) query = query.eq('stand_id', standId);
      final rows = await query.order('month');

      final byMonth = <String, MonthlySales>{};
      for (final row in rows) {
        final item = MonthlySales.fromMap(row);
        final key = '${item.month.year}-${item.month.month}';
        final prev = byMonth[key];
        byMonth[key] = prev == null
            ? item
            : MonthlySales(
                month: item.month,
                units: prev.units + item.units,
                amount: prev.amount + item.amount,
              );
      }
      return byMonth.values.toList()
        ..sort((a, b) => a.month.compareTo(b.month));
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------ Inventarios

  Future<List<InventoryDifference>> fetchDifferences({
    String? standId,
    int limit = 50,
  }) async {
    try {
      var query = _db.from(_differences).select();
      if (standId != null) query = query.eq('stand_id', standId);
      final rows = await query
          .order('completed_at', ascending: false)
          .limit(limit);
      return rows
          .map<InventoryDifference>((r) => InventoryDifference.fromMap(r))
          .toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }
}
