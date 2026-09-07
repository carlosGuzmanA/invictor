/// Detalle del conteo de un producto dentro de una jornada de inventario.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.inventoryId,
    required this.productId,
    required this.systemQty,
    this.countedQty,
    this.difference,
    this.photoUrl,
    this.note,
    this.countedAt,
    this.productName,
    this.sku,
  });

  final String id;
  final String inventoryId;
  final String productId;

  /// Stock del sistema congelado al abrir el inventario.
  final int systemQty;

  /// null = todavía sin contar.
  final int? countedQty;

  /// Columna GENERADA en PostgreSQL (contado − sistema). Solo lectura.
  final int? difference;

  final String? photoUrl;
  final String? note;
  final DateTime? countedAt;

  final String? productName;
  final String? sku;

  bool get isCounted => countedQty != null;
  bool get hasPhoto => photoUrl != null && photoUrl!.trim().isNotEmpty;
  bool get hasDifference => isCounted && (difference ?? 0) != 0;

  /// Regla §19: sin fotografía el conteo no puede cerrarse.
  bool get isReadyToClose => !isCounted || hasPhoto;

  factory InventoryItem.fromMap(Map<String, dynamic> map) => InventoryItem(
        id: map['id'] as String,
        inventoryId: map['inventory_id'] as String,
        productId: map['product_id'] as String,
        systemQty: (map['system_qty'] as num?)?.toInt() ?? 0,
        countedQty: (map['counted_qty'] as num?)?.toInt(),
        difference: (map['difference'] as num?)?.toInt(),
        photoUrl: map['photo_url'] as String?,
        note: map['note'] as String?,
        countedAt: DateTime.tryParse(map['counted_at']?.toString() ?? ''),
        productName: map['product_name'] as String? ??
            (map['products'] as Map<String, dynamic>?)?['name'] as String?,
        sku: map['sku'] as String? ??
            (map['products'] as Map<String, dynamic>?)?['sku'] as String?,
      );

  /// `difference` es columna generada: enviarla provoca error en PostgREST.
  Map<String, dynamic> toCountUpdateMap() => {
        'counted_qty': countedQty,
        'photo_url': photoUrl,
        'note': note,
        'counted_at': (countedAt ?? DateTime.now()).toIso8601String(),
      };
}
