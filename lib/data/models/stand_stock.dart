/// Existencia de un producto en un puesto concreto.
///
/// Es un saldo DERIVADO de `inventory_movements`, mantenido por trigger.
/// El cliente solo lo lee: RLS no permite escribirlo.
class StandStock {
  const StandStock({
    required this.standId,
    required this.productId,
    required this.quantity,
    this.standName,
    this.productName,
    this.sku,
    this.minStock = 0,
    this.updatedAt,
  });

  final String standId;
  final String productId;
  final int quantity;
  final String? standName;
  final String? productName;
  final String? sku;
  final int minStock;
  final DateTime? updatedAt;

  bool get isLow => quantity <= minStock;

  /// Cantidad negativa: se registraron salidas sobre stock que el sistema
  /// no conocía. No es un bug del cálculo, es un dato que hay que investigar.
  bool get isNegative => quantity < 0;

  factory StandStock.fromMap(Map<String, dynamic> map) => StandStock(
        standId: map['stand_id'] as String,
        productId: map['product_id'] as String,
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        standName: map['stand_name'] as String?,
        productName: map['product_name'] as String?,
        sku: map['sku'] as String?,
        minStock: (map['min_stock'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
      );
}
