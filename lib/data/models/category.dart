/// Clasificación de productos.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.active,
    this.description,
    this.icon,
  });

  final String id;
  final String name;
  final String? description;
  final bool active;

  /// Identificador semántico del icono ('peluche', 'llavero'…). Lo heredan sus
  /// productos cuando no tienen foto propia.
  final String? icon;

  factory Category.fromMap(Map<String, dynamic> map) => Category(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        active: (map['active'] as bool?) ?? true,
        icon: map['icon'] as String?,
      );

  /// Sin `id`: lo genera la base de datos.
  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'description': description,
        'active': active,
        'icon': icon,
      };

  Category copyWith({
    String? name,
    String? description,
    bool? active,
    String? icon,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        active: active ?? this.active,
        icon: icon ?? this.icon,
      );
}
