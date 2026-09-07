import 'package:flutter/material.dart';

import '../../../core/design/product_icons.dart';
import '../../../core/design/tokens.dart';

/// Selector de icono para un producto o una categoría.
///
/// Cuadrícula agrupada por tipo con buscador: con treinta iconos y creciendo,
/// obligar a recorrerlos todos cada vez sería peor que escribir "mochila".
class IconPickerSheet extends StatefulWidget {
  const IconPickerSheet({super.key, this.selected});

  final String? selected;

  /// Devuelve el id elegido, `''` si se quitó el icono, o null si se canceló.
  static Future<String?> show(BuildContext context, {String? selected}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => IconPickerSheet(selected: selected),
    );
  }

  @override
  State<IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<IconPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<IconGroup, List<ProductIcon>> get _visible {
    if (_search.trim().isEmpty) return ProductIcons.grouped;

    final q = _search.trim().toLowerCase();
    final result = <IconGroup, List<ProductIcon>>{};
    ProductIcons.grouped.forEach((group, icons) {
      final matches = icons
          .where((i) =>
              i.label.toLowerCase().contains(q) || i.id.contains(q))
          .toList();
      if (matches.isNotEmpty) result[group] = matches;
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = _visible;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.xl, 0, Space.xl, Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Elegir icono',
                          style: theme.textTheme.titleLarge),
                    ),
                    if (widget.selected != null)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(''),
                        child: const Text('Quitar'),
                      ),
                  ],
                ),
                const SizedBox(height: Space.md),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar: peluche, mochila, cuaderno…',
                    prefixIcon: const Icon(Icons.search, size: Sizes.icon),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xxl),
                      child: Text(
                        'Ningún icono coincide con "$_search".\n'
                        'Si necesitas uno nuevo, dilo y se agrega.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: Space.xxl),
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Space.gutter, Space.lg, Space.gutter, Space.sm),
                          child: Text(entry.key.label.toUpperCase(),
                              style: theme.textTheme.labelSmall),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Space.md),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 96,
                              mainAxisSpacing: Space.sm,
                              crossAxisSpacing: Space.sm,
                              mainAxisExtent: 84,
                            ),
                            itemCount: entry.value.length,
                            itemBuilder: (context, i) => _IconTile(
                              option: entry.value[i],
                              selected: entry.value[i].id == widget.selected,
                              onTap: () => Navigator.of(context)
                                  .pop(entry.value[i].id),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ProductIcon option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : null,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              option.icon,
              size: 26,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
            const SizedBox(height: Space.xs + 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              child: Text(
                option.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? theme.colorScheme.primary : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
