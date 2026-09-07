import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/utils/alert_sound.dart';
import '../providers/live_providers.dart';

/// Ajustes de los avisos en vivo.
class LiveSettingsSheet extends ConsumerWidget {
  const LiveSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const LiveSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final soundOn = ref.watch(soundAlertsProvider).value ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Avisos', style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.lg),

            SwitchListTile(
              value: soundOn,
              onChanged: (v) =>
                  ref.read(soundAlertsProvider.notifier).setEnabled(v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Sonido al registrarse una salida'),
              subtitle: const Text(
                'Un pitido corto cuando un vendedor registra una salida. '
                'Solo mientras el dashboard esté abierto.',
              ),
            ),

            if (soundOn) ...[
              const SizedBox(height: Space.sm),
              OutlinedButton.icon(
                onPressed: playAlertSound,
                icon: const Icon(Icons.volume_up_outlined, size: 18),
                label: const Text('Probar el sonido'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                ),
              ),
            ],

            const SizedBox(height: Space.lg),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      kIsWeb
                          // La política de autoplay del navegador es un
                          // límite real, no un detalle: conviene decirlo antes
                          // de que parezca que el ajuste no funciona.
                          ? 'En el navegador el sonido necesita que hayas '
                              'tocado la página antes. Con la pestaña cerrada '
                              'no hay aviso posible: eso requeriría '
                              'notificaciones push.'
                          : 'El aviso respeta el modo silencio del '
                              'dispositivo. Con la aplicación cerrada no hay '
                              'sonido.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
