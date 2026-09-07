import 'package:flutter/material.dart';

/// Catálogo de iconos elegibles para un producto o una categoría.
///
/// La base guarda un identificador de texto ('peluche', 'mochila'…) y no un
/// icono, para que no dependa de Material Icons: una futura app nativa puede
/// dibujar lo que quiera con el mismo dato.
///
/// Los iconos van como constantes literales a propósito. El
/// `--tree-shake-icons` de Flutter solo conserva los que ve referenciados en
/// el código, así que construirlos dinámicamente los borraría del build.
class ProductIcon {
  const ProductIcon(this.id, this.label, this.icon, this.group);

  final String id;
  final String label;
  final IconData icon;
  final IconGroup group;
}

enum IconGroup {
  peluches('Peluches y figuras'),
  bolsos('Mochilas y bolsos'),
  papeleria('Papelería'),
  ropa('Ropa y accesorios'),
  tematicas('Temáticas'),
  otros('Otros');

  const IconGroup(this.label);
  final String label;
}

class ProductIcons {
  const ProductIcons._();

  static const fallback = Icons.inventory_2_outlined;

  /// Ajustado al catálogo real: peluches de anime y franquicias, mochilas,
  /// muñecas articuladas, mini figuras, llaveros, libretas, stickers,
  /// camisetas y coleteros.
  static const all = <ProductIcon>[
    // Peluches y figuras
    ProductIcon('peluche', 'Peluche', Icons.toys, IconGroup.peluches),
    ProductIcon('muneca', 'Muñeca', Icons.child_care, IconGroup.peluches),
    ProductIcon('figura', 'Figura', Icons.person, IconGroup.peluches),
    ProductIcon('robot', 'Robot', Icons.smart_toy, IconGroup.peluches),
    ProductIcon('animal', 'Animal', Icons.pets, IconGroup.peluches),
    ProductIcon('coleccionable', 'Coleccionable', Icons.collections,
        IconGroup.peluches),

    // Mochilas y bolsos
    ProductIcon('mochila', 'Mochila', Icons.backpack, IconGroup.bolsos),
    ProductIcon('bolso', 'Bolso', Icons.shopping_bag, IconGroup.bolsos),
    ProductIcon('cartera', 'Cartera', Icons.work, IconGroup.bolsos),
    ProductIcon('llavero', 'Llavero', Icons.vpn_key, IconGroup.bolsos),

    // Papelería
    ProductIcon('cuaderno', 'Cuaderno', Icons.menu_book, IconGroup.papeleria),
    ProductIcon('libro', 'Libro', Icons.auto_stories, IconGroup.papeleria),
    ProductIcon('sticker', 'Stickers', Icons.sell, IconGroup.papeleria),
    ProductIcon('lapiz', 'Lápiz', Icons.edit, IconGroup.papeleria),
    ProductIcon('arte', 'Arte', Icons.palette, IconGroup.papeleria),

    // Ropa y accesorios. Los ids coinciden con los que ya asigna la
    // migración 0007 ('ropa', 'accesorio'): un identificador por concepto,
    // porque dos ids para el mismo icono confunden en el selector.
    ProductIcon('ropa', 'Ropa', Icons.checkroom, IconGroup.ropa),
    ProductIcon('accesorio', 'Accesorio de pelo', Icons.style, IconGroup.ropa),
    ProductIcon('joya', 'Joya', Icons.diamond, IconGroup.ropa),
    ProductIcon('reloj', 'Reloj', Icons.watch, IconGroup.ropa),

    // Temáticas
    ProductIcon('anime', 'Anime', Icons.theater_comedy, IconGroup.tematicas),
    ProductIcon(
        'videojuego', 'Videojuego', Icons.sports_esports, IconGroup.tematicas),
    ProductIcon('musica', 'Música / K-pop', Icons.music_note,
        IconGroup.tematicas),
    ProductIcon('pelicula', 'Película', Icons.movie, IconGroup.tematicas),
    ProductIcon('kawaii', 'Kawaii', Icons.favorite, IconGroup.tematicas),

    // Otros
    ProductIcon('tecnologia', 'Tecnología', Icons.headphones, IconGroup.otros),
    ProductIcon('hogar', 'Hogar', Icons.chair, IconGroup.otros),
    ProductIcon('dulce', 'Dulce', Icons.cookie, IconGroup.otros),
    ProductIcon('bebida', 'Bebida', Icons.local_cafe, IconGroup.otros),
    ProductIcon('regalo', 'Regalo', Icons.redeem, IconGroup.otros),
    ProductIcon('generico', 'Genérico', fallback, IconGroup.otros),
  ];

  static final _byId = {for (final i in all) i.id: i};

  /// Icono de un identificador. Devuelve el genérico si no hay valor o no se
  /// reconoce: un identificador nuevo en la base nunca debe romper la pantalla.
  static IconData resolve(String? id) {
    if (id == null) return fallback;
    return _byId[id.trim().toLowerCase()]?.icon ?? fallback;
  }

  /// Nombre legible, para mostrar cuál está elegido.
  static String? labelOf(String? id) {
    if (id == null) return null;
    return _byId[id.trim().toLowerCase()]?.label;
  }

  static bool isKnown(String? id) =>
      id != null && _byId.containsKey(id.trim().toLowerCase());

  /// Agrupados para el selector, en el orden de [IconGroup].
  static Map<IconGroup, List<ProductIcon>> get grouped {
    final map = <IconGroup, List<ProductIcon>>{};
    for (final group in IconGroup.values) {
      final items = all.where((i) => i.group == group).toList();
      if (items.isNotEmpty) map[group] = items;
    }
    return map;
  }

  static List<String> get ids => all.map((i) => i.id).toList();
}
