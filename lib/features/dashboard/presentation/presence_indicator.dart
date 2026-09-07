import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/presence_service.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/live_providers.dart';

/// Mantiene abierto el canal de presencia para **cualquier** usuario con
/// sesión, sin dibujar nada.
///
/// Hace falta porque un provider de Riverpod no se ejecuta hasta que alguien
/// lo observa. Con solo el indicador —que ve el staff— un vendedor jamás se
/// unía al canal, y el administrador se veía únicamente a sí mismo.
///
/// Va en un widget aparte, y no con un `watch` en el shell, para que un cambio
/// de presencia no reconstruya toda la pantalla del trabajador.
class PresenceTracker extends ConsumerWidget {
  const PresenceTracker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El valor no se usa: observar el provider es lo que publica mi presencia.
    ref.watch(onlineUsersProvider);
    return const SizedBox.shrink();
  }
}

/// Icono con el número de personas que tienen la app abierta.
///
/// Se muestra solo a staff: a un vendedor no le aporta saber quién más está
/// conectado, y sí añade ruido a una barra que ya lleva el selector de puesto.
class PresenceIndicator extends ConsumerWidget {
  const PresenceIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineUsersProvider);
    final theme = Theme.of(context);
    final count = online.value?.length ?? 0;

    return IconButton(
      tooltip: 'Quién tiene la app abierta',
      onPressed: () => OnlineUsersSheet.show(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.people_outline),
          if (count > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: theme.semantic.positive,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border:
                      Border.all(color: theme.colorScheme.surface, width: 1.5),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Listado de quién está conectado.
class OnlineUsersSheet extends ConsumerWidget {
  const OnlineUsersSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const OnlineUsersSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineUsersProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.xl, 0, Space.xl, Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Con la app abierta',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 2),
                  // El matiz importa: esto no dice quién está en su turno.
                  Text(
                    'Quien cierra la aplicación o bloquea el teléfono '
                    'desaparece de la lista, aunque siga en su puesto.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            online.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Space.xxl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.all(Space.xl),
                child: EmptyState(
                  icon: Icons.wifi_off,
                  title: 'Sin conexión en vivo',
                  detail: 'No se pudo abrir el canal de presencia.',
                ),
              ),
              data: (users) {
                if (users.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(Space.xl),
                    child: EmptyState(
                      icon: Icons.person_off_outlined,
                      title: 'Nadie conectado',
                      detail: 'Ni siquiera tú, lo que es raro: quizá el canal '
                          'aún está sincronizando.',
                    ),
                  );
                }

                return Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _UserRow(user: users[i]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final OnlineUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              user.name.characters.first.toUpperCase(),
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: semantic.positive,
                shape: BoxShape.circle,
                border:
                    Border.all(color: theme.colorScheme.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(user.name),
      subtitle: Text(
        [
          user.role.label,
          if (user.onlineAt != null) 'desde ${Fmt.time(user.onlineAt)}',
          if (user.devices > 1) '${user.devices} sesiones',
        ].join(' · '),
      ),
    );
  }
}
