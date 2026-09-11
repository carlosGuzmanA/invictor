/// Juegos de tallas listos para usar al crear un modelo.
///
/// Son plantillas, no una lista cerrada: se pueden quitar tallas y escribir
/// otras. Existen porque tecleando trece tallas a mano cada vez, alguien
/// acaba escribiendo «xl» una vez y «XL» la siguiente, y entonces son dos
/// productos distintos con el mismo nombre.
class SizeTemplate {
  const SizeTemplate({
    required this.name,
    required this.sizes,
    required this.priceBand,
  });

  final String name;
  final List<String> sizes;

  /// Con qué banda de precio nace cada talla de esta plantilla.
  final PriceBand priceBand;

  static const kids = SizeTemplate(
    name: 'Niño (2 a 16)',
    // De dos en dos, que es como vienen: no existe la talla 3.
    sizes: ['2', '4', '6', '8', '10', '12', '14', '16'],
    priceBand: PriceBand.kids,
  );

  static const adults = SizeTemplate(
    name: 'Adulto (S a XXL)',
    sizes: ['S', 'M', 'L', 'XL', 'XXL'],
    priceBand: PriceBand.adults,
  );

  static const shoes = SizeTemplate(
    name: 'Calzado (35 a 44)',
    sizes: ['35', '36', '37', '38', '39', '40', '41', '42', '43', '44'],
    priceBand: PriceBand.adults,
  );

  static const all = [kids, adults, shoes];
}

/// Las dos bandas de precio de una prenda.
///
/// La distinción es de precio, no de tamaño: las de niño valen una cosa y las
/// de adulto otra, y es la única razón por la que hace falta separarlas al
/// crear el modelo.
enum PriceBand {
  kids('Precio niño'),
  adults('Precio adulto');

  const PriceBand(this.label);
  final String label;
}

/// Una talla elegida, con la banda de precio que le toca.
class SizeChoice {
  const SizeChoice({
    required this.label,
    required this.band,
    required this.order,
  });

  final String label;
  final PriceBand band;

  /// Posición dentro del modelo. Sin esto las tallas se ordenan alfabéticas
  /// —L, M, S, XL— que no es como nadie las busca.
  final int order;
}
