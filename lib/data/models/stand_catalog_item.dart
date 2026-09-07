/// Una línea del catálogo operativo de un puesto (vista `v_stand_catalog`).
///
/// Es lo que necesitan la salida rápida (§4.1) y el conteo físico: producto,
/// cuánto hay en ESE puesto, y si pertenece al catálogo del puesto.
class StandCatalogItem {
  const StandCatalogItem({
    required this.standId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.inCatalog,
    this.standName,
    this.sku,
    this.categoryId,
    this.categoryName,
    this.price = 0,
    this.minStock = 0,
    this.updatedAt,
    this.categoryIcon,
    this.imageUrl,
    this.productIcon,
  });

  final String standId;
  final String? standName;
  final String productId;
  final String productName;
  final String? sku;
  final String? categoryId;
  final String? categoryName;

  /// Identificador semántico del icono ('peluche', 'llavero'…), heredado de la
  /// categoría. Lo traduce a un icono `ProductIcons.resolve`.
  final String? categoryIcon;

  /// Foto propia del producto, si la tiene. Tiene prioridad sobre el icono de
  /// la categoría al dibujar la tarjeta.
  final String? imageUrl;

  /// Icono elegido para este producto. Tiene prioridad sobre [categoryIcon].
  final String? productIcon;
  final double price;
  final int minStock;

  /// Existencia en este puesto. Puede ser negativa (ver [isNegative]).
  final int quantity;

  /// false = tiene saldo aquí pero no está asignado a este puesto.
  /// Ocurre, por ejemplo, tras un traslado. Se muestra igual: ocultar
  /// existencias reales sería peor que mostrarlas fuera de catálogo.
  final bool inCatalog;

  final DateTime? updatedAt;

  bool get isLow => quantity <= minStock;

  /// Se registraron salidas sobre stock que el sistema no conocía.
  bool get isNegative => quantity < 0;

  /// Producto con saldo que nadie asignó a este puesto: conviene revisarlo.
  bool get isUnexpected => !inCatalog && quantity != 0;

  factory StandCatalogItem.fromMap(Map<String, dynamic> map) =>
      StandCatalogItem(
        standId: map['stand_id'] as String,
        standName: map['stand_name'] as String?,
        productId: map['product_id'] as String,
        productName: map['product_name'] as String,
        sku: map['sku'] as String?,
        categoryId: map['category_id'] as String?,
        categoryName: map['category_name'] as String?,
        price: _toDouble(map['price']) ?? 0,
        minStock: (map['min_stock'] as num?)?.toInt() ?? 0,
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        inCatalog: (map['in_catalog'] as bool?) ?? false,
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
        categoryIcon: map['category_icon'] as String?,
        imageUrl: map['image_url'] as String?,
        productIcon: map['product_icon'] as String?,
      );

  /// Se usa para reflejar un movimiento al instante, antes de que el servidor
  /// confirme. El valor real lo repone el siguiente refresco.
  StandCatalogItem copyWith({int? quantity}) => StandCatalogItem(
        standId: standId,
        standName: standName,
        productId: productId,
        productName: productName,
        sku: sku,
        categoryId: categoryId,
        categoryName: categoryName,
        price: price,
        minStock: minStock,
        quantity: quantity ?? this.quantity,
        inCatalog: inCatalog,
        updatedAt: updatedAt,
        categoryIcon: categoryIcon,
        imageUrl: imageUrl,
        productIcon: productIcon,
      );

  static double? _toDouble(Object? value) => switch (value) {
        null => null,
        final num n => n.toDouble(),
        final String s => double.tryParse(s),
        _ => null,
      };
}
