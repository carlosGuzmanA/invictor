import 'package:flutter/material.dart';

/// Escala de espaciado. Múltiplos de 4: usar siempre estos valores en lugar de
/// números sueltos es lo que hace que las pantallas se vean del mismo sistema.
class Space {
  const Space._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Márgenes laterales del contenido.
  static const gutter = 16.0;
}

/// Radios de esquina. Pocos valores y consistentes.
class Radii {
  const Radii._();

  static const sm = 8.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const pill = 999.0;

  static const cardShape = BorderRadius.all(Radius.circular(md));
  static const sheetShape = BorderRadius.vertical(top: Radius.circular(lg));
}

class Insets {
  const Insets._();

  static const card = EdgeInsets.symmetric(
    horizontal: Space.lg,
    vertical: Space.md,
  );
  static const page = EdgeInsets.symmetric(horizontal: Space.gutter);
  static const sheet = EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl);
}

class Sizes {
  const Sizes._();

  /// Alto mínimo de un objetivo táctil. Se opera de pie y con el pulgar (§18).
  static const tapTarget = 52.0;

  /// Ancho máximo del contenido en escritorio. Sin esto, en el dashboard las
  /// filas se estiran a 1900 px y se vuelven ilegibles.
  static const contentMax = 880.0;
  static const wideContentMax = 1200.0;

  static const thumb = 44.0;
  static const icon = 20.0;
}

class Motion {
  const Motion._();

  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 200);
}
