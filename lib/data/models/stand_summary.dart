import '../../core/constants/enums.dart';

/// Indicadores de un puesto (vista `v_stand_summary`). Base del dashboard (§10).
class StandSummary {
  const StandSummary({
    required this.standId,
    required this.standName,
    required this.type,
    required this.active,
    required this.productsAssigned,
    required this.productsWithStock,
    required this.unitsTotal,
    required this.productsNegative,
    required this.productsLow,
    required this.exitsToday,
    required this.exitsWeek,
    required this.openInventories,
    this.lastMovementAt,
  });

  final String standId;
  final String standName;
  final StandType type;
  final bool active;

  final int productsAssigned;
  final int productsWithStock;
  final int unitsTotal;

  /// Saldo negativo: salidas sobre stock que el sistema no conocía.
  final int productsNegative;
  final int productsLow;

  /// Unidades salidas hoy, en día de Chile (lo calcula la base).
  final int exitsToday;
  final int exitsWeek;
  final int openInventories;
  final DateTime? lastMovementAt;

  int get alerts => productsNegative + productsLow;
  bool get needsAttention => alerts > 0;
  bool get isWarehouse => type == StandType.bodega;

  factory StandSummary.fromMap(Map<String, dynamic> map) => StandSummary(
        standId: map['stand_id'] as String,
        standName: map['stand_name'] as String,
        type: StandType.fromWire(map['type'] as String?),
        active: (map['active'] as bool?) ?? true,
        productsAssigned: (map['products_assigned'] as num?)?.toInt() ?? 0,
        productsWithStock: (map['products_with_stock'] as num?)?.toInt() ?? 0,
        unitsTotal: (map['units_total'] as num?)?.toInt() ?? 0,
        productsNegative: (map['products_negative'] as num?)?.toInt() ?? 0,
        productsLow: (map['products_low'] as num?)?.toInt() ?? 0,
        exitsToday: (map['exits_today'] as num?)?.toInt() ?? 0,
        exitsWeek: (map['exits_week'] as num?)?.toInt() ?? 0,
        openInventories: (map['open_inventories'] as num?)?.toInt() ?? 0,
        lastMovementAt:
            DateTime.tryParse(map['last_movement_at']?.toString() ?? ''),
      );
}

/// Producto bajo mínimo o con saldo negativo (vista `v_stock_alerts`).
class StockAlert {
  const StockAlert({
    required this.standId,
    required this.standName,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.minStock,
    required this.severity,
    this.sku,
    this.productIcon,
    this.categoryIcon,
    this.imageUrl,
  });

  final String standId;
  final String standName;
  final String productId;
  final String productName;
  final String? sku;
  final String? productIcon;
  final String? categoryIcon;
  final String? imageUrl;
  final int quantity;
  final int minStock;

  /// 'negativo' o 'bajo'. Lo decide la base para que ambos criterios vivan
  /// en un solo sitio.
  final String severity;

  bool get isNegative => severity == 'negativo';

  factory StockAlert.fromMap(Map<String, dynamic> map) => StockAlert(
        standId: map['stand_id'] as String,
        standName: map['stand_name'] as String,
        productId: map['product_id'] as String,
        productName: map['product_name'] as String,
        sku: map['sku'] as String?,
        productIcon: map['product_icon'] as String?,
        categoryIcon: map['category_icon'] as String?,
        imageUrl: map['image_url'] as String?,
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        minStock: (map['min_stock'] as num?)?.toInt() ?? 0,
        severity: (map['severity'] as String?) ?? 'bajo',
      );
}

/// Diferencia detectada en una jornada cerrada (vista `v_inventory_differences`).
class InventoryDifference {
  const InventoryDifference({
    required this.itemId,
    required this.inventoryId,
    required this.inventoryCode,
    required this.standId,
    required this.standName,
    required this.productId,
    required this.productName,
    required this.systemQty,
    required this.countedQty,
    required this.difference,
    this.sku,
    this.completedAt,
    this.profileName,
    this.photoUrl,
    this.note,
  });

  final String itemId;
  final String inventoryId;
  final int inventoryCode;
  final String standId;
  final String standName;
  final String productId;
  final String productName;
  final String? sku;
  final int systemQty;
  final int countedQty;
  final int difference;
  final DateTime? completedAt;
  final String? profileName;
  final String? photoUrl;
  final String? note;

  bool get hasPhoto => (photoUrl ?? '').trim().isNotEmpty;

  factory InventoryDifference.fromMap(Map<String, dynamic> map) =>
      InventoryDifference(
        itemId: map['item_id'] as String,
        inventoryId: map['inventory_id'] as String,
        inventoryCode: (map['inventory_code'] as num?)?.toInt() ?? 0,
        standId: map['stand_id'] as String,
        standName: map['stand_name'] as String,
        productId: map['product_id'] as String,
        productName: map['product_name'] as String,
        sku: map['sku'] as String?,
        systemQty: (map['system_qty'] as num?)?.toInt() ?? 0,
        countedQty: (map['counted_qty'] as num?)?.toInt() ?? 0,
        difference: (map['difference'] as num?)?.toInt() ?? 0,
        completedAt: DateTime.tryParse(map['completed_at']?.toString() ?? ''),
        profileName: map['profile_name'] as String?,
        photoUrl: map['photo_url'] as String?,
        note: map['note'] as String?,
      );
}
