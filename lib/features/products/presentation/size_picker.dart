import 'package:flutter/material.dart';

import '../../../core/constants/size_templates.dart';
import '../../../core/design/tokens.dart';

/// Elegir las tallas de un modelo y el precio de cada banda.
///
/// Las tallas de niño y las de adulto valen distinto, y esa es la única razón
/// por la que hay dos precios: no es una clasificación por tamaño sino por lo
/// que cuesta cada prenda.
///
/// Las plantillas existen porque tecleando trece tallas a mano cada vez,
/// alguien acaba escribiendo «xl» una vez y «XL» la siguiente — y entonces
/// son dos productos distintos con el mismo nombre.
class SizePicker extends StatefulWidget {
  const SizePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.enabled,
  });

  /// Talla -> banda de precio. El orden lo fija la plantilla.
  final Map<String, PriceBand> selected;
  final ValueChanged<Map<String, PriceBand>> onChanged;
  final bool enabled;

  @override
  State<SizePicker> createState() => _SizePickerState();
}

class _SizePickerState extends State<SizePicker> {
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _toggle(String size, PriceBand band) {
    final next = Map<String, PriceBand>.from(widget.selected);
    if (next.containsKey(size)) {
      next.remove(size);
    } else {
      next[size] = band;
    }
    widget.onChanged(next);
  }

  void _applyTemplate(SizeTemplate template) {
    final next = Map<String, PriceBand>.from(widget.selected);
    // Añade sin quitar: es normal querer niño Y adulto en el mismo modelo,
    // que es justo el caso que hace falta cubrir.
    final alreadyAll = template.sizes.every(next.containsKey);
    for (final size in template.sizes) {
      if (alreadyAll) {
        next.remove(size);
      } else {
        next[size] = template.priceBand;
      }
    }
    widget.onChanged(next);
  }

  void _addCustom() {
    final raw = _customCtrl.text.trim().toUpperCase();
    if (raw.isEmpty) return;
    final next = Map<String, PriceBand>.from(widget.selected);
    // Por defecto, adulto: una talla que no está en ninguna plantilla suele
    // ser de adulto («XXXL», «Única»).
    next.putIfAbsent(raw, () => PriceBand.adults);
    widget.onChanged(next);
    _customCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final template in SizeTemplate.all) ...[
          Row(
            children: [
              Expanded(
                child: Text(template.name, style: theme.textTheme.labelMedium),
              ),
              TextButton(
                onPressed: widget.enabled
                    ? () => _applyTemplate(template)
                    : null,
                child: Text(
                  template.sizes.every(widget.selected.containsKey)
                      ? 'Quitar todas'
                      : 'Añadir todas',
                ),
              ),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              for (final size in template.sizes)
                FilterChip(
                  label: Text(size),
                  selected: widget.selected.containsKey(size),
                  onSelected: widget.enabled
                      ? (_) => _toggle(size, template.priceBand)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: Space.md),
        ],

        // Lo que no está en ninguna plantilla: «Única», «XXXL», un número
        // suelto. Sin esto habría que crear el producto y editarlo después.
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customCtrl,
                enabled: widget.enabled,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Otra talla',
                  hintText: 'XXXL, Única…',
                  isDense: true,
                ),
                onSubmitted: (_) => _addCustom(),
              ),
            ),
            const SizedBox(width: Space.sm),
            IconButton(
              onPressed: widget.enabled ? _addCustom : null,
              icon: const Icon(Icons.add),
              tooltip: 'Añadir talla',
            ),
          ],
        ),

        // Las que no vinieron de una plantilla, para poder quitarlas.
        if (_extras.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              for (final size in _extras)
                InputChip(
                  label: Text(size),
                  onDeleted: widget.enabled
                      ? () => _toggle(size, widget.selected[size]!)
                      : null,
                ),
            ],
          ),
        ],

        if (widget.selected.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text(
            'Se crearán ${widget.selected.length} productos, uno por talla. '
            'Cada uno lleva su propio stock.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  /// Tallas elegidas que no pertenecen a ninguna plantilla.
  List<String> get _extras {
    final fromTemplates = {
      for (final t in SizeTemplate.all) ...t.sizes,
    };
    return widget.selected.keys
        .where((s) => !fromTemplates.contains(s))
        .toList()
      ..sort();
  }
}

/// Convierte lo elegido en la lista que espera el servicio, con su orden.
///
/// El orden sale de la plantilla y no del alfabeto: así las tallas salen
/// 2, 4, 6… y S, M, L, XL, y no L, M, S, XL, que no es como nadie las busca.
List<SizeChoice> toSizeChoices(Map<String, PriceBand> selected) {
  final order = <String, int>{};
  var index = 0;
  for (final template in SizeTemplate.all) {
    for (final size in template.sizes) {
      order.putIfAbsent(size, () => index);
      index += 10;
    }
  }

  final choices = [
    for (final entry in selected.entries)
      SizeChoice(
        label: entry.key,
        band: entry.value,
        // Las que no están en ninguna plantilla van al final, juntas.
        order: order[entry.key] ?? 9000,
      ),
  ]..sort((a, b) => a.order.compareTo(b.order));

  return choices;
}
