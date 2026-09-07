import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';

/// Aviso con cuenta atrás visible, botón de deshacer y botón de cerrar.
///
/// Un `SnackBar` corriente solo admite **una** acción, así que con "Deshacer"
/// no queda sitio para cerrarlo a mano. Aquí el contenido es propio y lleva
/// las dos, más una barra que se agota: sin ella no se sabe cuánto tiempo
/// queda para deshacer, y esperar sin saber si aún se puede es peor que no
/// tener la opción.
class UndoSnackBar {
  const UndoSnackBar._();

  static const duration = Duration(seconds: 5);

  static void show(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
    String undoLabel = 'Deshacer',
  }) {
    final messenger = ScaffoldMessenger.of(context);

    messenger
      // Encadenar salidas no debe apilar avisos: se descarta el anterior para
      // que el visible sea siempre el del último movimiento.
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          padding: EdgeInsets.zero,
          content: _UndoContent(
            message: message,
            undoLabel: undoLabel,
            onUndo: () {
              messenger.hideCurrentSnackBar();
              onUndo();
            },
            onClose: messenger.hideCurrentSnackBar,
          ),
        ),
      );
  }
}

class _UndoContent extends StatelessWidget {
  const _UndoContent({
    required this.message,
    required this.undoLabel,
    required this.onUndo,
    required this.onClose,
  });

  final String message;
  final String undoLabel;
  final VoidCallback onUndo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onDark = theme.snackBarTheme.contentTextStyle?.color ??
        theme.colorScheme.onInverseSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cuenta atrás: se agota justo cuando el aviso desaparece.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: 0),
          duration: UndoSnackBar.duration,
          curve: Curves.linear,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 2,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation(
              onDark.withValues(alpha: 0.55),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, Space.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: theme.snackBarTheme.contentTextStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.sm),
              TextButton(
                onPressed: onUndo,
                style: TextButton.styleFrom(
                  foregroundColor: onDark,
                  minimumSize: const Size(0, 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: Space.md),
                ),
                child: Text(undoLabel),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: onClose,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                color: onDark.withValues(alpha: 0.8),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
