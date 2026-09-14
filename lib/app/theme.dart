import 'package:flutter/material.dart';

import '../core/design/palette.dart';
import '../core/design/tokens.dart';

/// Tema de la aplicación: panel limpio y denso.
///
/// Criterios:
///   · Estructura con bordes finos, no con sombras. Las sombras suman ruido
///     visual y en listas densas emborronan la separación entre filas.
///   · Color solo donde significa algo (stock bajo, diferencia, error).
///   · Figtree, empaquetada. Antes se usaba la del sistema y la misma pantalla
///     se veía distinta en cada teléfono; Roboto por defecto, además, es la
///     firma de una aplicación que nadie miró. Va empaquetada y no enlazada a
///     un servidor de fuentes: así no hay petición externa al arrancar ni
///     salto de texto al llegar (ver `pubspec.yaml`).
///   · Cifras de ancho fijo en todo lo que es número. Una cantidad que pasa de
///     9 a 10 no debe mover la columna entera.
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
      surface: isDark ? Palette.sand950 : Colors.white,
      surfaceContainerLowest: isDark ? Palette.sand950 : Colors.white,
      surfaceContainerLow: isDark ? Palette.sand900 : Palette.sand50,
      surfaceContainer: isDark ? Palette.sand900 : Palette.sand50,
      surfaceContainerHigh: isDark ? Palette.sand800 : Palette.sand100,
      surfaceContainerHighest: isDark ? Palette.sand800 : Palette.sand100,
      onSurface: isDark ? Palette.sand100 : Palette.sand900,
      onSurfaceVariant: isDark ? Palette.sand400 : Palette.sand500,
      // El relleno de los botones suaves —el de «1 salida» de cada tarjeta— y
      // el del botón de crear. Se fijan a mano porque, derivados del terracota,
      // salían de un rosa salmón desvaído que no se parecía a la marca ni
      // pegaba con el resto: se vio en una captura, no en un test.
      secondaryContainer: isDark ? Palette.sand800 : Palette.brandSoft,
      onSecondaryContainer: isDark ? Palette.brandDark : Palette.brandDeep,
      outline: isDark ? Palette.sand700 : Palette.sand400,
      outlineVariant: isDark ? Palette.sand800 : Palette.sand200,
      error: isDark ? Palette.dangerDark : Palette.danger,
    );

    final text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      fontFamily: _family,
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
        // Un escalón más oscuro que el fondo de la pantalla, no el mismo.
        // Eran idénticos y el campo solo se distinguía por su borde: en la
        // pantalla de acceso, sobre fondo liso, parecían texto suelto con una
        // línea alrededor en vez de algo donde se escribe.
        fillColor: isDark ? Palette.sand800 : Palette.sand100,
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
        backgroundColor: isDark ? Palette.sand800 : Palette.sand900,
        contentTextStyle: text.bodyMedium?.copyWith(color: Palette.sand100),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        insetPadding: const EdgeInsets.all(Space.lg),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.outlineVariant,
        linearMinHeight: 6,
      ),

      // Terracota lleno, no el tono suave de los botones de cada tarjeta.
      // Antes los dos eran del mismo rosa y competían entre sí; crear un
      // producto pasa una vez al día y descontar cien, así que el que grita
      // tiene que ser el raro.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
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

  /// La familia empaquetada. Los pesos disponibles son 400, 500, 600 y 700:
  /// pedir otro haría que la plataforma lo fingiera engordando el trazo, que
  /// es justo lo que se quiso evitar al empaquetarla.
  static const _family = 'Figtree';

  /// Cifras de ancho fijo.
  ///
  /// Por defecto un «1» es más estrecho que un «8», así que una cantidad que
  /// pasa de 9 a 10 —o un contador que baja mientras se descuenta— cambia de
  /// ancho y empuja lo que tiene al lado. Con esto todas las cifras ocupan lo
  /// mismo: los números cambian sin que se mueva nada a su alrededor y las
  /// columnas de precios quedan alineadas solas.
  ///
  /// Va en **toda** la escala y no solo en los estilos que parecen numéricos.
  /// Se intentó lo segundo y salió mal enseguida: el precio de la tarjeta usa
  /// `titleLarge`, que no estaba en la lista, y se quedó sin alinear. En un
  /// inventario casi todo número es un dato que cambia, así que la lista de
  /// excepciones siempre iba a estar incompleta. En prosa no se nota.
  static const _tabular = [FontFeature.tabularFigures()];

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
          fontFamily: _family,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
          height: height,
          color: color ?? scheme.onSurface,
          fontFeatures: _tabular,
        );

    return base.copyWith(
      // Cifras grandes: contadores y métricas del panel.
      displaySmall:
          style(40, FontWeight.w700, spacing: -1.2, height: 1.05),
      headlineMedium:
          style(28, FontWeight.w700, spacing: -0.6, height: 1.15),
      headlineSmall:
          style(22, FontWeight.w700, spacing: -0.4, height: 1.2),

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
