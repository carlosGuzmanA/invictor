/// Producto del catálogo.
///
/// Ojo: NO tiene stock propio. El stock vive en `stand_stock` (por puesto).
/// Al leer desde la vista `v_product_stock` se rellenan [stockTotal] y
/// [lowStock]; al leer desde la tabla `products` quedan en null.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.minStock,
    required this.active,
    this.sku,
    this.categoryId,
    this.categoryName,
    this.cost,
    this.imageUrl,
    this.stockTotal,
    this.icon,
    this.priceConfirmed = true,
  });

  final String id;
  final String name;
  final String? sku;
  final String? categoryId;
  final String? categoryName;
  final double price;
  final double? cost;

  /// Umbral de alerta de stock bajo (§10).
  final int minStock;
  final String? imageUrl;

  /// Icono elegido ('peluche', 'mochila'…). Respaldo: el de su categoría.
  final String? icon;
  final bool active;

  /// Solo presente al leer desde `v_product_stock`.
  final int? stockTotal;

  /// false = lo registró un vendedor que no sabía el precio.
  ///
  /// El precio se guarda igual como 0, pero un 0 no distingue "gratis" de
  /// "todavía no lo sé". Esta bandera sí, y es lo que permite avisar en la
  /// interfaz hasta que el administrador lo complete.
  final bool priceConfirmed;

  /// Hay que preguntarle el precio al administrador.
  bool get needsPrice => !priceConfirmed;

  bool get isLowStock => stockTotal != null && stockTotal! <= minStock;

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        // La vista expone `product_id`; la tabla expone `id`.
        id: (map['id'] ?? map['product_id']) as String,
        name: map['name'] as String,
        sku: map['sku'] as String?,
        categoryId: map['category_id'] as String?,
        categoryName: map['category_name'] as String? ??
            (map['categories'] as Map<String, dynamic>?)?['name'] as String?,
        price: _toDouble(map['price']) ?? 0,
        cost: _toDouble(map['cost']),
        minStock: (map['min_stock'] as num?)?.toInt() ?? 0,
        imageUrl: map['image_url'] as String?,
        active: (map['active'] as bool?) ?? true,
        stockTotal: (map['stock_total'] as num?)?.toInt(),
        icon: map['icon'] as String? ?? map['product_icon'] as String?,
        priceConfirmed: (map['price_confirmed'] as bool?) ?? true,
      );

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'sku': sku,
        'category_id': categoryId,
        'price': price,
        'cost': cost,
        'min_stock': minStock,
        'image_url': imageUrl,
        'icon': icon,
        'active': active,
        'price_confirmed': priceConfirmed,
      };

  Product copyWith({
    String? name,
    String? sku,
    String? categoryId,
    double? price,
    double? cost,
    int? minStock,
    String? imageUrl,
    bool? active,
    int? stockTotal,
    String? icon,
    bool? priceConfirmed,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        sku: sku ?? this.sku,
        categoryId: categoryId ?? this.categoryId,
        categoryName: categoryName,
        price: price ?? this.price,
        cost: cost ?? this.cost,
        minStock: minStock ?? this.minStock,
        imageUrl: imageUrl ?? this.imageUrl,
        active: active ?? this.active,
        stockTotal: stockTotal ?? this.stockTotal,
        icon: icon ?? this.icon,
        priceConfirmed: priceConfirmed ?? this.priceConfirmed,
      );

  // `numeric` de PostgreSQL puede llegar como String por PostgREST.
  static double? _toDouble(Object? value) => switch (value) {
        null => null,
        final num n => n.toDouble(),
        final String s => double.tryParse(s),
        _ => null,
      };
}
