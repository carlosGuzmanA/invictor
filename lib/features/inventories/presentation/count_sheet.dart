import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/inventory_item.dart';
import '../../../services/photo_service.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Conteo físico de un producto (§4.2).
///
/// La fotografía se exige **solo cuando el conteo difiere del sistema**: si
/// coincide, la foto no prueba nada; si no coincide, es la evidencia del
/// descuadre. Esa misma regla la aplica `finalize_inventory()` en la base, así
/// que la interfaz no puede saltársela — solo evita el intento fallido.
class CountSheet extends ConsumerStatefulWidget {
  const CountSheet({
    super.key,
    required this.item,
    required this.standId,
  });

  final InventoryItem item;
  final String standId;

  static Future<bool> show(
    BuildContext context, {
    required InventoryItem item,
    required String standId,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CountSheet(item: item, standId: standId),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends ConsumerState<CountSheet> {
  late final TextEditingController _qtyCtrl = TextEditingController(
    text: widget.item.countedQty?.toString() ?? '',
  );
  late final TextEditingController _noteCtrl =
      TextEditingController(text: widget.item.note ?? '');

  CapturedPhoto? _photo;
  bool _busy = false;
  String? _error;

  /// Error crudo del último fallo de cámara. Se muestra en pequeño bajo el
  /// mensaje: en el móvil de un trabajador no hay consola del navegador, y sin
  /// esto no hay forma de saber qué falló realmente.
  String? _errorDetail;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int? get _counted => int.tryParse(_qtyCtrl.text.trim());
  int? get _difference =>
      _counted == null ? null : _counted! - widget.item.systemQty;

  bool get _hasDifference => (_difference ?? 0) != 0;

  /// Ya existía una foto guardada de un conteo anterior de este mismo producto.
  bool get _hasStoredPhoto => widget.item.hasPhoto;

  bool get _photoRequired => _hasDifference && !_hasStoredPhoto && _photo == null;

  Future<void> _takePhoto([
    ImageSource source = ImageSource.camera,
  ]) async {
    setState(() {
      _error = null;
      _errorDetail = null;
    });
    try {
      final photo = await ref.read(photoServiceProvider).capture(
            source: source,
          );
      if (photo == null) return; // cancelado, no es error
      if (mounted) setState(() => _photo = photo);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _errorDetail = technicalDetail(e);
        });
      }
    }
  }

  Future<void> _save() async {
    final invalid = Validators.countedQuantity(_qtyCtrl.text);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    if (_photoRequired) {
      setState(() => _error =
          'Hay diferencia con el sistema: la fotografía es obligatoria.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(inventoryServiceProvider).saveCount(
            item: widget.item,
            standId: widget.standId,
            countedQty: _counted!,
            photoBytes: _photo?.bytes,
            photoContentType: _photo?.contentType ?? 'image/jpeg',
            note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          );
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
    final item = widget.item;
    final diff = _difference;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.productName ?? 'Producto',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              [
                if (item.sku != null) item.sku!,
                'el sistema dice ${item.systemQty}',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _qtyCtrl,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '¿Cuántas unidades cuentas?',
                hintText: '0',
              ),
            ),

            if (diff != null) ...[
              const SizedBox(height: 16),
              _DifferenceBadge(systemQty: item.systemQty, counted: _counted!),
            ],

            const SizedBox(height: 20),
            _PhotoBox(
              required: _hasDifference,
              photo: _photo,
              hasStoredPhoto: _hasStoredPhoto,
              onTake: _busy ? null : _takePhoto,
              onPick: _busy ? null : () => _takePhoto(ImageSource.gallery),
              onClear: _photo == null ? null : () => setState(() => _photo = null),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observación (opcional)',
                prefixIcon: Icon(Icons.notes),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              if (_errorDetail != null) ...[
                const SizedBox(height: 6),
                SelectableText(
                  _errorDetail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],

            const SizedBox(height: 20),
            BusyButton(
              label: 'Guardar conteo',
              busy: _busy,
              onPressed: _save,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DifferenceBadge extends StatelessWidget {
  const _DifferenceBadge({required this.systemQty, required this.counted});

  final int systemQty;
  final int counted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = counted - systemQty;
    final ok = diff == 0;
    final color = ok ? theme.semantic.positive : theme.semantic.danger;

    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: Space.md, horizontal: Space.lg),
      decoration: BoxDecoration(
        color: ok
            ? theme.semantic.positiveSurface
            : theme.semantic.dangerSurface,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              size: 20, color: color),
          const SizedBox(width: 10),
          Text(
            ok
                ? 'Coincide con el sistema'
                : 'Diferencia ${diff > 0 ? '+$diff' : '$diff'}',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({
    required this.required,
    required this.photo,
    required this.hasStoredPhoto,
    required this.onTake,
    required this.onPick,
    required this.onClear,
  });

  final bool required;
  final CapturedPhoto? photo;
  final bool hasStoredPhoto;
  final VoidCallback? onTake;

  /// Abre el selector de archivos en vez de la cámara directa.
  ///
  /// Cuando `capture="environment"` falla —pasa en algunas PWA instaladas de
  /// Android— este es el camino que sigue funcionando: el selector del sistema
  /// ofrece la cámara igual, solo con un toque más.
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (photo != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              photo!.bytes,
              height: 180,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${photo!.sizeKb} KB'
                  '${photo!.reduction > 0.05 ? ' · ${(photo!.reduction * 100).round()} % menos' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              TextButton.icon(
                onPressed: onTake,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Repetir'),
              ),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Quitar'),
              ),
            ],
          ),
        ],
      );
    }

    if (hasStoredPhoto && !required) {
      return Row(
        children: [
          const Icon(Icons.photo_camera_back_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Ya hay una fotografía guardada',
                style: theme.textTheme.bodySmall),
          ),
          TextButton(onPressed: onTake, child: const Text('Reemplazar')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onTake,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(
            required ? 'Tomar fotografía (obligatoria)' : 'Tomar fotografía',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: required ? theme.colorScheme.error : null,
            side: required
                ? BorderSide(color: theme.colorScheme.error)
                : null,
          ),
        ),
        TextButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('Elegir archivo'),
        ),
      ],
    );
  }
}
