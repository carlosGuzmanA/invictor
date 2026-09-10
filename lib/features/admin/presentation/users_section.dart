import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/models/profile.dart';
import '../../../core/utils/password_generator.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/admin_providers.dart';

/// Usuarios: rol, estado y puestos asignados.
///
/// El **alta** se hace en Supabase Auth y no aquí: crear usuarios exige la
/// service_role key, que nunca debe viajar al navegador. Esta pantalla asigna
/// a quien ya existe su rol y sus puestos.
class UsersSection extends ConsumerWidget {
  const UsersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(allProfilesProvider);
    final me = ref.watch(currentProfileProvider).value;
    final isAdmin = me?.isAdmin ?? false;

    return Column(
      children: [
        _NewUserHint(isAdmin: isAdmin),
        Expanded(
          child: profiles.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar los usuarios',
              detail: e is AppException ? e.message : '$e',
              tone: EmptyTone.danger,
              onAction: () => ref.invalidate(allProfilesProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.people_outline,
                  title: 'Sin usuarios',
                  detail: 'Créalos en Supabase → Authentication → Users.',
                );
              }
              return ContentWidth(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: Space.xxl),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _UserRow(
                    profile: list[i],
                    isSelf: list[i].id == me?.id,
                    canEdit: isAdmin,
                    onTap: isAdmin
                        ? () => _UserSheet.show(context, profile: list[i]).then(
                            (changed) {
                              if (changed) {
                                ref.invalidate(allProfilesProvider);
                              }
                            },
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NewUserHint extends StatelessWidget {
  const _NewUserHint({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.sm,
      ),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              isAdmin
                  ? 'Los usuarios se crean en Supabase → Authentication → '
                        'Users. Aquí se les asigna rol y puestos.'
                  : 'Puedes consultar los usuarios; cambiar roles y puestos '
                        'requiere rol de administrador.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({
    required this.profile,
    required this.isSelf,
    required this.canEdit,
    required this.onTap,
  });

  final Profile profile;
  final bool isSelf;
  final bool canEdit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;
    final stands = ref.watch(profileStandsProvider(profile.id));

    final roleColor = switch (profile.role) {
      UserRole.admin => semantic.danger,
      UserRole.encargado => semantic.info,
      UserRole.vendedor => theme.colorScheme.onSurfaceVariant,
    };

    // Un vendedor sin puestos no ve nada: conviene que salte a la vista.
    final standsLabel = stands.when(
      loading: () => '…',
      error: (_, _) => '—',
      data: (list) => list.isEmpty
          ? 'sin puestos asignados'
          : list.map((s) => s.name).join(' · '),
    );
    final needsStands =
        profile.role == UserRole.vendedor &&
        profile.active &&
        (stands.value?.isEmpty ?? false);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: roleColor.withValues(alpha: 0.12),
        child: Text(
          profile.displayName.characters.first.toUpperCase(),
          style: theme.textTheme.titleSmall?.copyWith(color: roleColor),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(profile.displayName, overflow: TextOverflow.ellipsis),
          ),
          if (isSelf) ...[
            const SizedBox(width: Space.sm),
            StatusPill(label: 'Tú', color: theme.colorScheme.primary),
          ],
          if (!profile.active) ...[
            const SizedBox(width: Space.sm),
            StatusPill(
              label: 'Inactivo',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile.email ?? 'sin correo'),
          const SizedBox(height: 2),
          Row(
            children: [
              StatusPill(label: profile.role.label, color: roleColor),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Text(
                  standsLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: needsStands ? semantic.warning : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: onTap == null
          ? null
          : Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.outline,
            ),
    );
  }
}

/// Edición de rol, estado y puestos de un usuario.
class _UserSheet extends ConsumerStatefulWidget {
  const _UserSheet({required this.profile});

  final Profile profile;

  static Future<bool> show(
    BuildContext context, {
    required Profile profile,
  }) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UserSheet(profile: profile),
    );
    return changed ?? false;
  }

  @override
  ConsumerState<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends ConsumerState<_UserSheet> {
  late UserRole _role = widget.profile.role;
  late bool _active = widget.profile.active;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  bool get _isSelf =>
      widget.profile.id == ref.read(currentProfileProvider).value?.id;

  /// Manda el enlace de restablecimiento al correo del usuario.
  ///
  /// No cambia la contraseña directamente: eso exige una clave de servicio
  /// que jamás debe viajar al navegador. Resuelve el caso real igual —el
  /// administrador manda el enlace, lo abre y define la nueva— y evita
  /// tener que entrar al panel de Supabase cada vez.
  Future<void> _sendReset() async {
    final email = widget.profile.email ?? '';
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Enlace enviado a $email. Si es un alias tuyo, '
                'te llega a ti: ábrelo y define la contraseña nueva.'),
            duration: const Duration(seconds: 6),
          ),
        );
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ));
      }
    }
  }

  /// Fija una contraseña temporal y la deja a la vista para dictarla.
  ///
  /// La persona queda obligada a cambiarla al entrar: una clave que el
  /// administrador conoce no identifica a nadie, y el historial atribuiría a
  /// su dueño lo que registre cualquiera que la haya oído.
  Future<void> _setTemporaryPassword() async {
    final controller = TextEditingController(text: generatePassword(length: 10));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Contraseña temporal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Dísela a ${widget.profile.displayName}. Al entrar tendrá '
                'que sustituirla antes de poder hacer nada.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
              // En claro y seleccionable: hay que poder leerla en voz alta o
              // copiarla, y ocultar algo que se va a dictar no protege nada.
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  helperText: 'Mínimo 8 caracteres',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Fijar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final password = controller.text.trim();
    setState(() => _busy = true);
    try {
      final warning = await ref.read(adminServiceProvider).setTemporaryPassword(
            profileId: widget.profile.id,
            password: password,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(allProfilesProvider);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(warning ??
                'Listo. Dile que entre con «$password» y elija una nueva.'),
            duration: const Duration(seconds: 10),
          ),
        );
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ));
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _changed = true;
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleStand(String standId, bool assigned) async {
    final service = ref.read(adminServiceProvider);
    await _run(() async {
      if (assigned) {
        await service.removeStand(widget.profile.id, standId);
      } else {
        await service.assignStand(widget.profile.id, standId);
      }
      ref.invalidate(profileStandsProvider(widget.profile.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allStands = ref.watch(allStandsProvider);
    final assigned = ref.watch(profileStandsProvider(widget.profile.id));
    final assignedIds = (assigned.value ?? const []).map((s) => s.id).toSet();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: EdgeInsets.only(
          left: Space.xl,
          right: Space.xl,
          bottom: MediaQuery.of(context).viewInsets.bottom + Space.xl,
        ),
        children: [
          Text(widget.profile.displayName, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            widget.profile.email ?? 'sin correo',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.xl),

          Text('ROL', style: theme.textTheme.labelSmall),
          const SizedBox(height: Space.sm),
          SegmentedButton<UserRole>(
            segments: [
              for (final r in UserRole.values)
                ButtonSegment(value: r, label: Text(r.label)),
            ],
            selected: {_role},
            onSelectionChanged: _busy || _isSelf
                ? null
                : (sel) {
                    final next = sel.first;
                    setState(() => _role = next);
                    _run(
                      () => ref
                          .read(adminServiceProvider)
                          .updateRole(widget.profile.id, next),
                    );
                  },
          ),
          if (_isSelf) ...[
            const SizedBox(height: Space.sm),
            Text(
              'No puedes cambiar tu propio rol ni desactivarte: si te quitas '
              'el acceso, nadie podría devolvértelo desde la app.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: Space.xl),

          SwitchListTile(
            value: _active,
            onChanged: _busy || _isSelf
                ? null
                : (v) {
                    setState(() => _active = v);
                    _run(
                      () => ref
                          .read(adminServiceProvider)
                          .setActive(widget.profile.id, v),
                    );
                  },
            contentPadding: EdgeInsets.zero,
            title: const Text('Cuenta activa'),
            subtitle: const Text(
              'Al desactivarla deja de ver el catálogo, el stock y sus '
              'puestos —lo aplica la base, no la pantalla— y no puede '
              'entrar. Su historial de movimientos se conserva.',
            ),
          ),
          const SizedBox(height: Space.md),

          // Cambiar la contraseña de otro usuario exige la clave
          // `service_role`, que jamás puede viajar al navegador: quien la
          // tuviera se saltaría RLS entero. Lo que sí se puede hacer sin
          // ella es pedirle a Supabase que mande el enlace.
          //
          // Con vendedores sin correo real, la vía es darlos de alta con un
          // alias del propio administrador —`tu+juan@tucorreo.com`—: es una
          // dirección distinta para Supabase y el mensaje llega a su buzón.
          // La vía directa: se fija una temporal y se le dice de viva voz.
          // Es lo único que funciona cuando el correo es inventado y el
          // enlace de restablecimiento no llega a ninguna parte.
          OutlinedButton.icon(
            onPressed: _busy || _isSelf ? null : _setTemporaryPassword,
            icon: const Icon(Icons.vpn_key),
            label: const Text('Poner contraseña temporal'),
          ),
          const SizedBox(height: Space.xs),
          OutlinedButton.icon(
            onPressed: _busy || (widget.profile.email ?? '').isEmpty
                ? null
                : _sendReset,
            icon: const Icon(Icons.mail_outline),
            label: const Text('Enviar enlace al correo'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              (widget.profile.email ?? '').isEmpty
                  ? 'Sin correo: solo la contraseña temporal, o el panel de '
                      'Supabase.'
                  : 'El enlace solo sirve si el correo existe de verdad.',
              style: theme.textTheme.labelSmall,
            ),
          ),
          const Divider(height: Space.xxl),

          Text('PUESTOS ASIGNADOS', style: theme.textTheme.labelSmall),
          const SizedBox(height: Space.xs),
          Text(
            _role.isStaff
                ? 'Un ${_role.label.toLowerCase()} accede a todos los puestos '
                      'aunque no tenga ninguno asignado.'
                : 'Un vendedor sin puestos asignados no ve stock ni '
                      'movimientos: lo impide RLS.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.sm),

          allStands.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(
              e is AppException ? e.message : '$e',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            data: (stands) => Column(
              children: [
                for (final stand in stands.where((s) => s.active))
                  CheckboxListTile(
                    value: assignedIds.contains(stand.id),
                    onChanged: _busy
                        ? null
                        : (_) => _toggleStand(
                            stand.id,
                            assignedIds.contains(stand.id),
                          ),
                    contentPadding: EdgeInsets.zero,
                    title: Text(stand.name),
                    subtitle: Text(stand.type.label),
                    secondary: Icon(
                      stand.isWarehouse ? Icons.warehouse : Icons.storefront,
                      size: Sizes.icon,
                    ),
                  ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: Space.md),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],

          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(_changed),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }
}
