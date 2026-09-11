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
    this.parentId,
    this.variantLabel,
    this.variantOrder = 0,
    this.parentName,
    this.parentImageUrl,
    this.parentIcon,
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

  /// Modelo del que esta línea es una talla. Null = producto suelto.
  ///
  /// Una polera son trece productos con stock y precio propios; esto es lo
  /// único que dice que son la misma polera.
  final String? parentId;

  /// La talla tal como se lee: «8», «S», «XXL».
  final String? variantLabel;

  /// Orden de presentación. Sin esto las tallas salen alfabéticas —L, M, S,
  /// XL— que no es como nadie las busca.
  final int variantOrder;

  /// Nombre, foto e icono del modelo. Vienen en la vista para que la tarjeta
  /// agrupada no necesite una consulta por cada grupo.
  final String? parentName;
  final String? parentImageUrl;
  final String? parentIcon;

  /// Es una talla de un modelo y no un producto suelto.
  bool get isVariant => parentId != null;

  /// Con qué agrupar en pantalla: el modelo si lo tiene, o el producto mismo.
  String get groupId => parentId ?? productId;

  /// Cómo llamar al grupo.
  String get groupName => parentName ?? productName;

  /// Cómo llamar a esta línea dentro de su grupo.
  String get shortLabel => variantLabel ?? productName;

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
        parentId: map['parent_id'] as String?,
        variantLabel: map['variant_label'] as String?,
        variantOrder: (map['variant_order'] as num?)?.toInt() ?? 0,
        parentName: map['parent_name'] as String?,
        parentImageUrl: map['parent_image_url'] as String?,
        parentIcon: map['parent_icon'] as String?,
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
        parentId: parentId,
        variantLabel: variantLabel,
        variantOrder: variantOrder,
        parentName: parentName,
        parentImageUrl: parentImageUrl,
        parentIcon: parentIcon,
      );

  static double? _toDouble(Object? value) => switch (value) {
        null => null,
        final num n => n.toDouble(),
        final String s => double.tryParse(s),
        _ => null,
      };
}
