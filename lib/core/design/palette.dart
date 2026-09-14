import 'package:flutter/material.dart';

/// Paleta de la aplicación.
///
/// Criterio de siempre: color **solo para significado** — stock bajo,
/// diferencia, error. Si el color decora, deja de informar; en un puesto con
/// prisa lo único que debe saltar a la vista es lo que va mal.
///
/// Lo que cambió: la marca era `#2563EB` y los neutros la escala *slate*, que
/// son literalmente los valores por defecto de Tailwind. Funcionaban, pero no
/// decían nada: cualquier aplicación sacada de una plantilla se ve así, y
/// esta vende peluches y juguetes en un centro comercial, no gestiona
/// servidores.
///
/// Ahora la marca es un terracota tostado y los neutros son cálidos, tirando
/// a arena. La advertencia anterior decía que los neutros cálidos «parecen
/// sucios» bajo luz fluorescente: es cierto con beige claro y poco contraste,
/// y por eso estos llevan el tinte justo para leerse cálidos sin perder
/// contraste — el salto de luminosidad entre escalones es el mismo que había.
///
/// **Cuidado al tocar esto:** una marca naranja-rojiza se acerca peligrosamente
/// a los colores de error y de alerta. Están separados a propósito: el rojo es
/// más puro y más claro que la marca, y la alerta se movió de ámbar a dorado.
/// Acercarlos de nuevo haría que un stock negativo pase por decoración.
class Palette {
  const Palette._();

  // --- Marca ----------------------------------------------------------------
  /// Terracota tostado. Oscuro a propósito: es el relleno de los botones
  /// principales y necesita texto blanco encima que se lea de un vistazo.
  static const brand = Color(0xFF9A4A26);

  /// El terracota rebajado a fondo: el relleno de los botones suaves, los que
  /// aparecen en cada tarjeta. Tiene que leerse como la marca diluida y no
  /// como un rosa: la diferencia está en conservar el marrón de fondo.
  static const brandSoft = Color(0xFFF3E3D8);

  /// Y el texto que va encima de ese fondo. Más oscuro que la marca para que
  /// un botón pequeño se lea sin forzar la vista.
  static const brandDeep = Color(0xFF6E3318);

  /// En tema oscuro el mismo tono no vale: sobre fondo negro hay que subir la
  /// luminosidad o el botón desaparece.
  static const brandDark = Color(0xFFF0A278);

  // --- Neutros cálidos ------------------------------------------------------
  //
  // Arena, no gris azulado. Es el cambio que más se nota sin que nadie sepa
  // decir por qué: los mismos componentes sobre un fondo templado dejan de
  // parecer un panel de administración.
  static const sand950 = Color(0xFF17110E);
  static const sand900 = Color(0xFF241B16);
  static const sand800 = Color(0xFF372A23);
  static const sand700 = Color(0xFF4F3E35);
  static const sand500 = Color(0xFF857266);
  static const sand400 = Color(0xFFA69184);
  static const sand300 = Color(0xFFC9B7A8);
  static const sand200 = Color(0xFFE5D9CC);
  static const sand100 = Color(0xFFF2EAE1);
  static const sand50 = Color(0xFFFBF7F2);

  // --- Semánticos -----------------------------------------------------------
  /// Stock correcto, conteo que cuadra.
  static const positive = Color(0xFF2E7D57);
  static const positiveDark = Color(0xFF6EE7B7);

  /// Stock bajo: avisa, no alarma.
  ///
  /// Dorado y no ámbar anaranjado. El ámbar de antes era casi el mismo tono
  /// que la marca nueva, y un aviso que parece el color corporativo deja de
  /// avisar.
  ///
  /// Oscuro para un dorado, y con motivo: el primero que se probó era más
  /// claro y se quedaba en 4,0 de contraste sobre blanco, por debajo del
  /// mínimo legible. En un pasillo con claraboyas eso es un aviso que no se
  /// ve, que es lo mismo que no ponerlo.
  static const warning = Color(0xFF8A6D06);
  static const warningDark = Color(0xFFF5D547);

  /// Diferencia, stock negativo, error.
  ///
  /// Rojo más puro y más claro que la marca, para que no se confundan. Es la
  /// distinción que más importa de toda la paleta: un saldo negativo tiene que
  /// leerse como un problema, no como parte del decorado.
  ///
  /// Vivo a propósito. El primer rojo que se puso quedaba a cuatro centésimas
  /// de saturación del terracota: al lado de la marca se leía como una
  /// variante suya, no como una alarma. Lo que los separa no es el tono —están
  /// cerca en el círculo— sino que este es mucho más intenso.
  static const danger = Color(0xFFD32029);
  static const dangerDark = Color(0xFFFF8A80);

  /// Información neutra (jornada abierta, en curso).
  ///
  /// Azul acero: el único frío que queda, y por eso funciona como contrapunto
  /// de todo lo demás.
  static const info = Color(0xFF2A6F97);
  static const infoDark = Color(0xFF7DD3FC);
}

/// Colores con significado, resueltos según el brillo del tema.
///
/// Se exponen como extensión del ThemeData para no tener que decidir en cada
/// widget si toca la variante clara o la oscura.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.positive,
    required this.warning,
    required this.danger,
    required this.info,
    required this.positiveSurface,
    required this.warningSurface,
    required this.dangerSurface,
    required this.infoSurface,
  });

  final Color positive;
  final Color warning;
  final Color danger;
  final Color info;

  final Color positiveSurface;
  final Color warningSurface;
  final Color dangerSurface;
  final Color infoSurface;

  factory SemanticColors.of(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    Color surface(Color c) => c.withValues(alpha: dark ? 0.18 : 0.10);

    final positive = dark ? Palette.positiveDark : Palette.positive;
    final warning = dark ? Palette.warningDark : Palette.warning;
    final danger = dark ? Palette.dangerDark : Palette.danger;
    final info = dark ? Palette.infoDark : Palette.info;

    return SemanticColors(
      positive: positive,
      warning: warning,
      danger: danger,
      info: info,
      positiveSurface: surface(positive),
      warningSurface: surface(warning),
      dangerSurface: surface(danger),
      infoSurface: surface(info),
    );
  }

  @override
  SemanticColors copyWith({
    Color? positive,
    Color? warning,
    Color? danger,
    Color? info,
    Color? positiveSurface,
    Color? warningSurface,
    Color? dangerSurface,
    Color? infoSurface,
  }) =>
      SemanticColors(
        positive: positive ?? this.positive,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        info: info ?? this.info,
        positiveSurface: positiveSurface ?? this.positiveSurface,
        warningSurface: warningSurface ?? this.warningSurface,
        dangerSurface: dangerSurface ?? this.dangerSurface,
        infoSurface: infoSurface ?? this.infoSurface,
      );

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      positive: Color.lerp(positive, other.positive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      positiveSurface: Color.lerp(positiveSurface, other.positiveSurface, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
      infoSurface: Color.lerp(infoSurface, other.infoSurface, t)!,
    );
  }
}

extension SemanticColorsX on ThemeData {
  SemanticColors get semantic =>
      extension<SemanticColors>() ?? SemanticColors.of(brightness);
}

extension SemanticContextX on BuildContext {
  SemanticColors get semantic => Theme.of(this).semantic;
}
