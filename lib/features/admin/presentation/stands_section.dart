import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/stand.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../providers/admin_providers.dart';
import 'admin_screen.dart';
import 'stand_products_sheet.dart';

/// Puestos, carritos y bodegas.
class StandsSection extends ConsumerWidget {
  const StandsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stands = ref.watch(allStandsProvider);
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;

    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Puesto'),
            )
          : null,
      body: Column(
        children: [
          if (!isAdmin) const AdminOnlyNotice(what: 'crearlos o editarlos'),
          Expanded(
            child: stands.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudieron cargar los puestos',
                detail: e is AppException ? e.message : '$e',
                tone: EmptyTone.danger,
                onAction: () => ref.invalidate(allStandsProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'Sin puestos',
                    detail: 'Crea el primero para empezar a registrar stock.',
                  );
                }
                return ContentWidth(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _StandRow(
                      stand: list[i],
                      canEdit: isAdmin,
                      onEdit: () => _edit(context, ref, list[i]),
                      onProducts: () =>
                          StandProductsSheet.show(context, stand: list[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Stand? stand) async {
    final saved = await _StandFormSheet.show(context, stand: stand);
    if (saved) ref.invalidate(allStandsProvider);
  }
}

class _StandRow extends StatelessWidget {
  const _StandRow({
    required this.stand,
    required this.canEdit,
    required this.onEdit,
    required this.onProducts,
  });

  final Stand stand;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onProducts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: canEdit ? onEdit : null,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(
          stand.isWarehouse ? Icons.warehouse : Icons.storefront,
          size: 20,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(stand.name, overflow: TextOverflow.ellipsis)),
          if (!stand.active) ...[
            const SizedBox(width: Space.sm),
            StatusPill(
              label: 'Inactivo',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          stand.type.label,
          if (stand.location != null) stand.location!,
        ].join(' · '),
      ),
      trailing: IconButton(
        tooltip: 'Productos de este puesto',
        icon: const Icon(Icons.inventory_2_outlined),
        onPressed: onProducts,
      ),
    );
  }
}

/// Alta y edición de un puesto.
class _StandFormSheet extends ConsumerStatefulWidget {
  const _StandFormSheet({this.stand});

  final Stand? stand;

  static Future<bool> show(BuildContext context, {Stand? stand}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StandFormSheet(stand: stand),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<_StandFormSheet> createState() => _StandFormSheetState();
}

class _StandFormSheetState extends ConsumerState<_StandFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.stand?.name ?? '');
  late final _locationCtrl = TextEditingController(
    text: widget.stand?.location ?? '',
  );

  late StandType _type = widget.stand?.type ?? StandType.puesto;
  late bool _active = widget.stand?.active ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.stand == null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final service = ref.read(catalogServiceProvider);
      final location = _locationCtrl.text.trim();
      final stand = Stand(
        id: widget.stand?.id ?? '',
        name: _nameCtrl.text.trim(),
        location: location.isEmpty ? null : location,
        type: _type,
        active: _active,
      );

      if (_isNew) {
        await service.createStand(stand);
      } else {
        await service.updateStand(stand);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isNew ? 'Nuevo puesto' : 'Editar puesto',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Space.xl),

              TextFormField(
                controller: _nameCtrl,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Mall Curicó - Puesto 1',
                ),
                validator: (v) => Validators.required(v, 'El nombre'),
              ),
              const SizedBox(height: Space.md),

              TextFormField(
                controller: _locationCtrl,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Ubicación',
                  hintText: 'opcional',
                ),
              ),
              const SizedBox(height: Space.md),

              DropdownButtonFormField<StandType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final t in StandType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _type = v ?? StandType.puesto),
              ),

              if (!_isNew) ...[
                const SizedBox(height: Space.sm),
                SwitchListTile(
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  subtitle: const Text(
                    'Un puesto inactivo deja de aparecer, pero conserva su '
                    'historial y su stock.',
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: Space.md),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],

              const SizedBox(height: Space.xl),
              BusyButton(
                label: _isNew ? 'Crear puesto' : 'Guardar cambios',
                busy: _busy,
                onPressed: _save,
              ),
              const SizedBox(height: Space.sm),
            ],
          ),
        ),
      ),
    );
  }
}
