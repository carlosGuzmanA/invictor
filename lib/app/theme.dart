import 'package:flutter/material.dart';

import '../core/design/palette.dart';
import '../core/design/tokens.dart';

/// Tema de la aplicación: panel limpio y denso.
///
/// Criterios:
///   · Estructura con bordes finos, no con sombras. Las sombras suman ruido
///     visual y en listas densas emborronan la separación entre filas.
///   · Color solo donde significa algo (stock bajo, diferencia, error).
///   · Tipografía del sistema — SF en iPhone, Roboto en Android. Descargar una
///     fuente en tiempo de ejecución costaría cientos de KB y un salto de texto
///     al cargar, justo lo que no queremos en una PWA usada con datos móviles.
///   · Objetivos táctiles grandes: se opera de pie y con el pulgar (§18).
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: Palette.brand,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? Palette.brandDark : Palette.brand,
      surface: isDark ? Palette.slate950 : Colors.white,
      surfaceContainerLowest: isDark ? Palette.slate950 : Colors.white,
      surfaceContainerLow: isDark ? Palette.slate900 : Palette.slate50,
      surfaceContainer: isDark ? Palette.slate900 : Palette.slate50,
      surfaceContainerHigh: isDark ? Palette.slate800 : Palette.slate100,
      surfaceContainerHighest: isDark ? Palette.slate800 : Palette.slate100,
      onSurface: isDark ? Palette.slate100 : Palette.slate900,
      onSurfaceVariant: isDark ? Palette.slate400 : Palette.slate500,
      outline: isDark ? Palette.slate700 : Palette.slate400,
      outlineVariant: isDark ? Palette.slate800 : Palette.slate200,
      error: isDark ? Palette.dangerDark : Palette.danger,
    );

    final text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      textTheme: text,
      // Compacta las listas sin llegar a apretarlas.
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      extensions: [SemanticColors.of(brightness)],

      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        shape: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),

      // Tarjetas delimitadas por borde, sin sombra: en listas densas la sombra
      // ensucia y el borde separa mejor.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardShape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(Sizes.tapTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(Sizes.tapTarget),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Palette.slate900 : Palette.slate50,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md + 2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),

      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        backgroundColor: scheme.surface,
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
        showCheckmark: false,
      ),

      listTileTheme: ListTileThemeData(
        minVerticalPadding: Space.md,
        horizontalTitleGap: Space.md,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.xs,
        ),
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetShape),
        clipBehavior: Clip.antiAlias,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? Palette.slate800 : Palette.slate900,
        contentTextStyle: text.bodyMedium?.copyWith(color: Palette.slate100),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        insetPadding: const EdgeInsets.all(Space.lg),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.outlineVariant,
        linearMinHeight: 6,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        elevation: 2,
        surfaceTintColor: Colors.transparent,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }

  /// Escala tipográfica compacta. Los tamaños bajan respecto a los de Material
  /// por defecto y el peso sube: es lo que da la sensación de panel en vez de
  /// aplicación de consumo.
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = ThemeData(brightness: scheme.brightness).textTheme;

    TextStyle style(
      double size,
      FontWeight weight, {
      double spacing = 0,
      double? height,
      Color? color,
    }) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: height,
          color: color ?? scheme.onSurface,
        );

    return base.copyWith(
      // Cifras grandes: contadores y métricas.
      displaySmall: style(40, FontWeight.w700, spacing: -1.2, height: 1.05),
      headlineMedium: style(28, FontWeight.w700, spacing: -0.6, height: 1.15),
      headlineSmall: style(22, FontWeight.w700, spacing: -0.4, height: 1.2),

      titleLarge: style(19, FontWeight.w600, spacing: -0.3),
      titleMedium: style(16, FontWeight.w600, spacing: -0.15),
      titleSmall: style(14, FontWeight.w600, spacing: -0.05),

      bodyLarge: style(15, FontWeight.w500, height: 1.35),
      bodyMedium: style(14, FontWeight.w400, height: 1.4),
      bodySmall: style(13, FontWeight.w400,
          height: 1.35, color: scheme.onSurfaceVariant),

      labelLarge: style(15, FontWeight.w600, spacing: 0.1),
      labelMedium: style(13, FontWeight.w500, spacing: 0.1),
      labelSmall: style(11.5, FontWeight.w500,
          spacing: 0.3, color: scheme.onSurfaceVariant),
    );
  }
}
