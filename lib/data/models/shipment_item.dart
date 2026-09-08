/// Línea de una encomienda: un producto y sus cantidades.
///
/// [sentQty] es null en una encomienda a ciegas —el administrador no declaró
/// cantidades— y [receivedQty] lo es hasta que el vendedor confirma. Un 0 en
/// [receivedQty] es una respuesta válida y distinta de null: se esperaba el
/// producto y no llegó nada.
class ShipmentItem {
  const ShipmentItem({
    required this.id,
    required this.shipmentId,
    required this.productId,
    this.sentQty,
    this.receivedQty,
    this.missingQty,
    this.photoUrl,
    this.productName,
    this.sku,
    this.productImageUrl,
    this.productIcon,
    this.categoryIcon,
    this.price,
    this.priceConfirmed = true,
  });

  final String id;
  final String shipmentId;
  final String productId;

  /// Lo que el administrador declaró despachar. null en encomienda a ciegas.
  final int? sentQty;

  /// Lo que el vendedor confirmó. null mientras no la haya recibido.
  final int? receivedQty;

  /// Se calcula en la base (`sent_qty - received_qty`), no se escribe.
  ///
  /// El faltante no genera movimiento: lo que no llegó nunca estuvo en el
  /// puesto, así que descontarlo sería inventar una salida. Sirve para
  /// reclamar al transporte, y ahí es donde vive.
  final int? missingQty;

  final String? photoUrl;

  // --- Datos del producto, solo al leer desde `v_shipment_items` ---
  final String? productName;
  final String? sku;
  final String? productImageUrl;
  final String? productIcon;
  final String? categoryIcon;
  final double? price;

  /// false = hay que preguntarle el precio al administrador.
  final bool priceConfirmed;

  bool get hasPhoto => (photoUrl ?? '').isNotEmpty;

  /// Llegó menos de lo despachado.
  bool get isMissing => (missingQty ?? 0) > 0;

  /// Se despachó y no llegó absolutamente nada.
  bool get isFullyMissing =>
      sentQty != null && receivedQty != null && receivedQty == 0;

  factory ShipmentItem.fromMap(Map<String, dynamic> map) => ShipmentItem(
        id: map['id'] as String,
        shipmentId: map['shipment_id'] as String,
        productId: map['product_id'] as String,
        sentQty: (map['sent_qty'] as num?)?.toInt(),
        receivedQty: (map['received_qty'] as num?)?.toInt(),
        missingQty: (map['missing_qty'] as num?)?.toInt(),
        photoUrl: map['photo_url'] as String?,
        productName: map['product_name'] as String?,
        sku: map['sku'] as String?,
        productImageUrl: map['product_image_url'] as String?,
        productIcon: map['product_icon'] as String?,
        categoryIcon: map['category_icon'] as String?,
        price: _toDouble(map['price']),
        priceConfirmed: (map['price_confirmed'] as bool?) ?? true,
      );

  /// Solo lo que escribe el administrador al despachar.
  ///
  /// `received_qty` y `missing_qty` se omiten: el primero lo fija
  /// `receive_shipment()` y el segundo es una columna generada, que PostgREST
  /// rechaza si se envía.
  Map<String, dynamic> toInsertMap() => {
        'shipment_id': shipmentId,
        'product_id': productId,
        'sent_qty': sentQty,
        'photo_url': photoUrl,
      };

  /// Lo que espera `receive_shipment()` en su parámetro `p_items`.
  Map<String, dynamic> toReceiveMap(int quantity, {String? photoUrl}) => {
        'product_id': productId,
        'received_qty': quantity,
        'photo_url': photoUrl ?? this.photoUrl,
      };

  // `numeric` de PostgreSQL puede llegar como String por PostgREST.
  static double? _toDouble(Object? value) => switch (value) {
        null => null,
        final num n => n.toDouble(),
        final String s => double.tryParse(s),
        _ => null,
      };
}
