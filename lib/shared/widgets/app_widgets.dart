import 'package:flutter/material.dart';

import '../../core/design/palette.dart';
import '../../core/design/tokens.dart';

/// Piezas que se repiten en varias pantallas. Tenerlas en un sitio es lo que
/// impide que cada pantalla derive por su cuenta.

/// Limita el ancho del contenido en pantallas grandes.
///
/// Sin esto, en el dashboard de escritorio las filas se estiran a todo el
/// monitor y el ojo pierde el renglón entre el nombre y la cifra.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = Sizes.contentMax,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Estado vacío o de error, con acción opcional.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.tone = EmptyTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EmptyTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (tone) {
      EmptyTone.neutral => theme.colorScheme.onSurfaceVariant,
      EmptyTone.danger => theme.semantic.danger,
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(height: Space.lg),
            Text(title,
                style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (onAction != null) ...[
              const SizedBox(height: Space.xl),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh, size: Sizes.icon),
                label: Text(actionLabel ?? 'Reintentar'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum EmptyTone { neutral, danger }

/// Número con signo y color según su significado: verde suma, rojo resta.
class DeltaText extends StatelessWidget {
  const DeltaText(
    this.value, {
    super.key,
    this.style,
    this.neutralWhenZero = true,
  });

  final int value;
  final TextStyle? style;
  final bool neutralWhenZero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    final color = value == 0 && neutralWhenZero
        ? theme.colorScheme.onSurfaceVariant
        : value > 0
            ? semantic.positive
            : semantic.danger;

    final text = value == 0
        ? '0'
        : value > 0
            ? '+$value'
            : '−${value.abs()}';

    return Text(
      text,
      style: (style ?? theme.textTheme.titleMedium)?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Cifra grande con etiqueta. La unidad de medida del dashboard.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.tone,
    this.icon,
    this.onTap,
  });

  final String value;
  final String label;
  final Color? tone;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.onSurface;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardShape,
        child: Padding(
          padding: Insets.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: color),
                const SizedBox(height: Space.sm),
              ],
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta breve de estado. Color de fondo tenue, texto del mismo tono.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.background,
  });

  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm + 2,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: Space.xs + 1),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado de sección dentro de una lista.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(),
                style: theme.textTheme.labelSmall),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Fila de filtros desplazable horizontalmente.
class FilterRow extends StatelessWidget {
  const FilterRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// Barra fija inferior, separada por un borde en vez de una sombra.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: ContentWidth(child: child),
        ),
      ),
    );
  }
}

/// Botón que muestra progreso sin cambiar de tamaño al pulsarlo.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: Space.sm),
                ],
                Text(label),
              ],
            ),
    );
  }
}
