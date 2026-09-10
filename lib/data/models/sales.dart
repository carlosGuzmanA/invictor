/// Modelos de ventas estimadas.
///
/// **Estimadas, no facturación.** El sistema registra salidas, no pagos (§1):
/// los cobros van por Mercado Pago y aquí no hay descuentos ni precio final.
/// Sirve para comparar temporadas y ordenar productos por rotación.
library;

/// Totales de un período y del anterior de la misma duración, para comparar.
class SalesSummary {
  const SalesSummary({
    required this.units,
    required this.amount,
    required this.products,
    required this.prevUnits,
    required this.prevAmount,
  });

  final int units;
  final double amount;

  /// Productos distintos vendidos en el período.
  final int products;

  final int prevUnits;
  final double prevAmount;

  /// Variación del importe respecto al período anterior, entre -1 y +∞.
  ///
  /// null cuando el período anterior fue cero: un crecimiento «infinito» no
  /// dice nada y es peor que no mostrar el dato.
  double? get amountChange {
    if (prevAmount <= 0) return null;
    return (amount - prevAmount) / prevAmount;
  }

  double? get unitsChange {
    if (prevUnits <= 0) return null;
    return (units - prevUnits) / prevUnits;
  }

  bool get isGrowing => (amountChange ?? 0) > 0;

  /// Precio medio por unidad. Útil para detectar que se vendió más barato.
  double get averageTicket => units == 0 ? 0 : amount / units;

  static const empty = SalesSummary(
    units: 0,
    amount: 0,
    products: 0,
    prevUnits: 0,
    prevAmount: 0,
  );

  factory SalesSummary.fromMap(Map<String, dynamic> map) => SalesSummary(
        units: (map['units'] as num?)?.toInt() ?? 0,
        amount: _num(map['amount']),
        products: (map['products'] as num?)?.toInt() ?? 0,
        prevUnits: (map['prev_units'] as num?)?.toInt() ?? 0,
        prevAmount: _num(map['prev_amount']),
      );
}

/// Ventas de un día concreto, para el gráfico de barras.
class DailySales {
  const DailySales({
    required this.date,
    required this.units,
    required this.amount,
  });

  final DateTime date;
  final int units;
  final double amount;

  factory DailySales.fromMap(Map<String, dynamic> map) => DailySales(
        date: DateTime.tryParse(map['sale_date']?.toString() ?? '') ??
            DateTime.now(),
        units: (map['units'] as num?)?.toInt() ?? 0,
        amount: _num(map['amount']),
      );
}

/// Un producto en el ranking de ventas.
///
/// Incluye los que vendieron **cero**: el dato que sirve para decidir qué
/// retirar no es el peor de los que se vendieron, sino el que lleva semanas
/// parado con stock encima.
class ProductSales {
  const ProductSales({
    required this.productId,
    required this.productName,
    required this.units,
    required this.amount,
    required this.stockNow,
    this.sku,
    this.categoryName,
    this.productIcon,
    this.categoryIcon,
    this.imageUrl,
    this.lastSaleAt,
    this.daysSinceSale,
  });

  final String productId;
  final String productName;
  final String? sku;
  final String? categoryName;
  final String? productIcon;
  final String? categoryIcon;
  final String? imageUrl;

  final int units;
  final double amount;
  final int stockNow;

  final DateTime? lastSaleAt;

  /// null = nunca se ha vendido.
  final int? daysSinceSale;

  bool get neverSold => lastSaleAt == null;

  /// Parado: sin ventas en el período pero con existencias. Es capital
  /// inmovilizado, y lo que conviene mirar para rotar el surtido.
  bool get isStagnant => units <= 0 && stockNow > 0;

  /// Valor del stock parado, al precio medio de venta si lo hubo.
  double get stockValueEstimate =>
      units > 0 ? (amount / units) * stockNow : 0;

  factory ProductSales.fromMap(Map<String, dynamic> map) => ProductSales(
        productId: map['product_id'] as String,
        productName: map['product_name'] as String,
        sku: map['sku'] as String?,
        categoryName: map['category_name'] as String?,
        productIcon: map['product_icon'] as String?,
        categoryIcon: map['category_icon'] as String?,
        imageUrl: map['image_url'] as String?,
        units: (map['units'] as num?)?.toInt() ?? 0,
        amount: _num(map['amount']),
        stockNow: (map['stock_now'] as num?)?.toInt() ?? 0,
        lastSaleAt: DateTime.tryParse(map['last_sale_at']?.toString() ?? ''),
        daysSinceSale: (map['days_since_sale'] as num?)?.toInt(),
      );
}

/// Ventas de un mes, para ver temporadas.
class MonthlySales {
  const MonthlySales({
    required this.month,
    required this.units,
    required this.amount,
  });

  final DateTime month;
  final int units;
  final double amount;

  factory MonthlySales.fromMap(Map<String, dynamic> map) => MonthlySales(
        month:
            DateTime.tryParse(map['month']?.toString() ?? '') ?? DateTime.now(),
        units: (map['units'] as num?)?.toInt() ?? 0,
        amount: _num(map['amount']),
      );
}

/// Ventas de un puesto en un período.
///
/// «Actividad por puesto» ya existía, pero mide stock y movimientos: dice
/// cuánto hay y cuánto se movió, no cuánto se vendió. Comparar locales entre
/// sí —qué carrito rinde y cuál no— necesita el dinero, y esto es lo que lo
/// trae.
class StandSales {
  const StandSales({
    required this.standId,
    required this.standName,
    required this.units,
    required this.amount,
  });

  final String standId;
  final String standName;
  final int units;
  final double amount;

  /// Precio medio por unidad vendida.
  ///
  /// Distingue el puesto que vende mucho barato del que vende poco caro: dos
  /// locales pueden facturar lo mismo por razones opuestas.
  double get averageTicket => units == 0 ? 0 : amount / units;

  factory StandSales.fromMap(Map<String, dynamic> map) => StandSales(
        standId: map['stand_id'] as String,
        standName: map['stand_name'] as String? ?? 'Puesto',
        units: (map['units'] as num?)?.toInt() ?? 0,
        amount: _num(map['amount']),
      );
}

/// Ventas de una persona en un período.
///
/// El dato estaba desde el primer día: `inventory_movements.profile_id`
/// guarda quién registró cada salida. Faltaba agregarlo y enseñarlo.
class SellerSales {
  const SellerSales({
    required this.profileId,
    required this.units,
    required this.amount,
    this.name,
    this.email,
    this.stands = const [],
  });

  final String? profileId;
  final int units;
  final double amount;

  /// Null cuando quien consulta no puede leer ese perfil.
  ///
  /// La policy de `profiles` reserva los nombres a staff, así que un vendedor
  /// se ve a sí mismo y ve al resto sin nombre. No es un fallo: puede saber
  /// cuánto vendió él, no cuánto vendieron sus compañeros.
  final String? name;
  final String? email;

  /// En qué puestos vendió. Un vendedor puede cubrir más de uno.
  final List<String> stands;

  double get averageTicket => units == 0 ? 0 : amount / units;

  /// Con qué llamarle en pantalla.
  String get displayName =>
      name ?? email ?? (profileId == null ? 'Sin registrar' : 'Otro vendedor');

  /// El movimiento no guardó quién lo hizo. Pasa con los ajustes que genera
  /// el cierre de inventario, que no tienen autor humano.
  bool get isUnattributed => profileId == null;

  factory SellerSales.fromMap(Map<String, dynamic> map) => SellerSales(
        profileId: map['profile_id'] as String?,
        name: map['seller_name'] as String?,
        email: map['seller_email'] as String?,
        units: (map['units'] as num?)?.toInt() ?? 0,
        amount: _num(map['amount']),
        stands: [
          if (map['stand_name'] != null) map['stand_name'] as String,
        ],
      );
}

/// `numeric` de PostgreSQL puede llegar como String por PostgREST.
double _num(Object? value) => switch (value) {
      null => 0,
      final num n => n.toDouble(),
      final String s => double.tryParse(s) ?? 0,
      _ => 0,
    };
