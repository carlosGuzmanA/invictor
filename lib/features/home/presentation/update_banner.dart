import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/build_info.dart';
import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/reload_app.dart';
import '../providers/update_providers.dart';

/// Aviso de versión nueva disponible.
///
/// Aparece solo cuando lo publicado difiere de lo que se ejecuta. No se
/// recarga por su cuenta a propósito: hacerlo mientras alguien registra una
/// salida o cuenta un inventario le haría perder lo que está escribiendo.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateStatusProvider).value;
    if (status == null || !status.hasUpdate) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Material(
      color: theme.semantic.infoSurface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.sm,
            Space.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt,
                size: 18,
                color: theme.semantic.info,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Hay una versión nueva disponible',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.semantic.info,
                  ),
                ),
              ),
              TextButton(
                onPressed: reloadApp,
                style: TextButton.styleFrom(
                  foregroundColor: theme.semantic.info,
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Actualizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ficha de versión para el menú y la pantalla de diagnóstico.
class VersionTile extends ConsumerWidget {
  const VersionTile({super.key, this.dense = true});

  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(updateStatusProvider).value;

    final (icon, color, detail) = switch (status) {
      null => (
        Icons.hourglass_empty,
        theme.colorScheme.onSurfaceVariant,
        'comprobando…',
      ),
      final s when s.hasUpdate => (
        Icons.system_update_alt,
        theme.semantic.info,
        'hay una versión nueva',
      ),
      final s when s.unknown => (
        Icons.cloud_off,
        theme.colorScheme.onSurfaceVariant,
        'no se pudo comprobar',
      ),
      _ => (Icons.check_circle_outline, theme.semantic.positive, 'al día'),
    };

    final built = BuildInfo.builtAtDate;

    return ListTile(
      dense: dense,
      contentPadding: dense ? EdgeInsets.zero : null,
      leading: Icon(icon, color: color, size: dense ? 20 : 24),
      title: Text(BuildInfo.label),
      subtitle: Text(
        [
          detail,
          if (built != null) 'compilada ${Fmt.relative(built)}',
        ].join(' · '),
      ),
      trailing: (status?.hasUpdate ?? false)
          ? TextButton(onPressed: reloadApp, child: const Text('Actualizar'))
          : null,
    );
  }
}
