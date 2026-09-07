import 'package:flutter/material.dart';

/// Paleta de la aplicación.
///
/// Criterio: neutros fríos para la estructura y color **solo para significado**
/// — stock bajo, diferencia, error. Si el color decora, deja de informar; en un
/// puesto con prisa lo único que debe saltar a la vista es lo que va mal.
///
/// Los grises son fríos (slate) para que se lean bien bajo la luz fluorescente
/// de un centro comercial, donde los neutros cálidos parecen sucios.
class Palette {
  const Palette._();

  // --- Marca ----------------------------------------------------------------
  static const brand = Color(0xFF2563EB); // azul de acción
  static const brandDark = Color(0xFF60A5FA);

  // --- Neutros --------------------------------------------------------------
  static const slate950 = Color(0xFF0B1120);
  static const slate900 = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);
  static const slate700 = Color(0xFF334155);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate50 = Color(0xFFF8FAFC);

  // --- Semánticos -----------------------------------------------------------
  /// Stock correcto, conteo que cuadra.
  static const positive = Color(0xFF15803D);
  static const positiveDark = Color(0xFF4ADE80);

  /// Stock bajo: avisa, no alarma.
  static const warning = Color(0xFFB45309);
  static const warningDark = Color(0xFFFBBF24);

  /// Diferencia, stock negativo, error.
  static const danger = Color(0xFFB91C1C);
  static const dangerDark = Color(0xFFF87171);

  /// Información neutra (jornada abierta, en curso).
  static const info = Color(0xFF0E7490);
  static const infoDark = Color(0xFF22D3EE);
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
