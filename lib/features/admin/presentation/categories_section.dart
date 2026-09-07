import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/product_icons.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/category.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../products/presentation/icon_picker_sheet.dart';
import '../../products/providers/product_providers.dart';
import '../providers/admin_providers.dart';

/// Categorías y su icono de respaldo.
///
/// El icono de la categoría es el que heredan sus productos cuando no tienen
/// uno propio ni fotografía, así que elegirlo bien ahorra trabajo después.
class CategoriesSection extends ConsumerWidget {
  const CategoriesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(allCategoriesProvider);
    final isStaff = ref.watch(currentProfileProvider).value?.isStaff ?? false;

    return Scaffold(
      floatingActionButton: isStaff
          ? FloatingActionButton.extended(
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Categoría'),
            )
          : null,
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'No se pudieron cargar las categorías',
          detail: e is AppException ? e.message : '$e',
          tone: EmptyTone.danger,
          onAction: () => ref.invalidate(allCategoriesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              title: 'Sin categorías',
              detail: 'Agrupan los productos y les dan un icono por defecto.',
            );
          }
          return ContentWidth(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _CategoryRow(
                category: list[i],
                onTap: isStaff ? () => _edit(context, ref, list[i]) : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Category? category,
  ) async {
    final saved = await _CategoryFormSheet.show(context, category: category);
    if (saved) {
      ref.invalidate(allCategoriesProvider);
      // También el selector del formulario de producto: si no, una categoría
      // recién creada no aparecería ahí hasta reiniciar.
      ref.invalidate(productCategoriesProvider);
    }
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.onTap});

  final Category category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(
          ProductIcons.resolve(category.icon),
          size: 20,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(category.name, overflow: TextOverflow.ellipsis)),
          if (!category.active) ...[
            const SizedBox(width: Space.sm),
            StatusPill(
              label: 'Inactiva',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
      subtitle: Text(
        category.description ??
            ProductIcons.labelOf(category.icon) ??
            'Sin icono asignado',
      ),
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

class _CategoryFormSheet extends ConsumerStatefulWidget {
  const _CategoryFormSheet({this.category});

  final Category? category;

  static Future<bool> show(BuildContext context, {Category? category}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryFormSheet(category: category),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(
    text: widget.category?.name ?? '',
  );
  late final _descCtrl = TextEditingController(
    text: widget.category?.description ?? '',
  );

  late String? _iconId = widget.category?.icon;
  late bool _active = widget.category?.active ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.category == null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final chosen = await IconPickerSheet.show(context, selected: _iconId);
    if (chosen == null || !mounted) return;
    setState(() => _iconId = chosen.isEmpty ? null : chosen);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final service = ref.read(catalogServiceProvider);
      final desc = _descCtrl.text.trim();
      final category = Category(
        id: widget.category?.id ?? '',
        name: _nameCtrl.text.trim(),
        description: desc.isEmpty ? null : desc,
        active: _active,
        icon: _iconId,
      );

      if (_isNew) {
        await service.createCategory(category);
      } else {
        await service.updateCategory(category);
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
                _isNew ? 'Nueva categoría' : 'Editar categoría',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Space.xl),

              // El icono es tocable, igual que en el formulario de producto.
              Row(
                children: [
                  InkWell(
                    onTap: _busy ? null : _pickIcon,
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: Icon(
                        ProductIcons.resolve(_iconId),
                        size: 30,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ProductIcons.labelOf(_iconId) ?? 'Sin icono',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Lo heredan los productos de esta categoría que no '
                          'tengan icono ni foto propia.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xl),

              TextFormField(
                controller: _nameCtrl,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => Validators.required(v, 'El nombre'),
              ),
              const SizedBox(height: Space.md),

              TextFormField(
                controller: _descCtrl,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  hintText: 'opcional',
                ),
              ),

              if (!_isNew) ...[
                const SizedBox(height: Space.sm),
                SwitchListTile(
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activa'),
                  subtitle: const Text(
                    'Los productos que ya la usan la conservan.',
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: Space.md),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],

              const SizedBox(height: Space.xl),
              BusyButton(
                label: _isNew ? 'Crear categoría' : 'Guardar cambios',
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
