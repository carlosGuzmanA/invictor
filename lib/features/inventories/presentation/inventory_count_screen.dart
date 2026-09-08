import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/camera_permission.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/inventory.dart';
import '../../../data/models/inventory_item.dart';
import '../../../services/photo_service.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/evidence_photo.dart';
import '../../movements/providers/movement_providers.dart';
import '../../stands/providers/stand_providers.dart';
import '../providers/inventory_providers.dart';
import 'count_sheet.dart';

/// Jornada de inventario en curso: contar producto a producto y cerrar (§8).
class InventoryCountScreen extends ConsumerStatefulWidget {
  const InventoryCountScreen({super.key, required this.inventoryId});

  final String inventoryId;

  @override
  ConsumerState<InventoryCountScreen> createState() =>
      _InventoryCountScreenState();
}

class _InventoryCountScreenState
    extends ConsumerState<InventoryCountScreen> {
  bool _closing = false;
  bool _onlyPending = false;

  Future<void> _count(InventoryItem item, String standId) async {
    final saved = await CountSheet.show(context,
        item: item, standId: standId);
    if (!saved || !mounted) return;
    ref.invalidate(inventoryItemsProvider(widget.inventoryId));
    ref.invalidate(inventoryDetailProvider(widget.inventoryId));
  }

  Future<void> _attachOverview(Inventory inventory) async {
    // Mismo caso que en el conteo: en la PWA instalada el permiso de cámara
    // es el del WebAPK y `<input capture>` no lo pide.
    final gate = await ensureCameraAccess();
    if (!mounted) return;
    switch (gate) {
      case CameraGate.blocked:
        _snack(cameraBlockedMessage, error: true);
        return;
      case CameraGate.justGranted:
        _snack('Cámara habilitada. Pulsa otra vez para tomar la fotografía.');
        return;
      case CameraGate.ready:
        break;
    }

    CapturedPhoto? photo;
    try {
      photo = await ref.read(photoServiceProvider).capture();
    } on AppException catch (e) {
      // El detalle técnico va en el mismo aviso: aquí no hay dónde
      // desplegarlo y sin él un fallo de cámara es indiagnosticable.
      final detail = technicalDetail(e);
      if (mounted) {
        _snack(detail == null ? e.message : '${e.message}\n$detail',
            error: true);
      }
      return;
    }
    if (photo == null || !mounted) return;

    try {
      await ref.read(inventoryServiceProvider).saveOverviewPhoto(
            inventoryId: inventory.id,
            standId: inventory.standId,
            bytes: photo.bytes,
            contentType: photo.contentType,
          );
      if (!mounted) return;
      ref.invalidate(inventoryDetailProvider(widget.inventoryId));
      _snack('Fotografía de vitrina guardada (${photo.sizeKb} KB)');
    } on AppException catch (e) {
      if (mounted) _snack(e.message, error: true);
    }
  }

  Future<void> _finalize() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar la jornada?'),
        content: const Text(
          'Se generará un ajuste por cada diferencia encontrada y el stock '
          'quedará cuadrado. Una jornada cerrada no se puede reabrir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar jornada'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _closing = true);
    try {
      await ref
          .read(inventoryServiceProvider)
          .finalizeInventory(widget.inventoryId);
      if (!mounted) return;

      // El cierre generó movimientos de ajuste: el stock y el historial cambian.
      ref.invalidate(inventoriesProvider);
      ref.invalidate(openInventoryProvider);
      ref.invalidate(activeStandCatalogProvider);
      ref.invalidate(movementHistoryProvider);

      Navigator.of(context).pop();
      _snack('Jornada cerrada y stock cuadrado');
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _closing = false);
        _snack(e.message, error: true);
      }
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(inventoryDetailProvider(widget.inventoryId));
    final items = ref.watch(inventoryItemsProvider(widget.inventoryId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        // Sin ellipsis el título se lleva todo el ancho en pantallas estrechas
        // y deja las acciones con 1 px: RenderFlex overflow.
        title: Text(
          detail.value == null
              ? 'Inventario'
              : 'Inventario #${detail.value!.code}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        actions: [
          IconButton(
            tooltip: _onlyPending ? 'Ver todos' : 'Ver solo pendientes',
            icon: Icon(_onlyPending
                ? Icons.filter_alt
                : Icons.filter_alt_outlined),
            onPressed: () => setState(() => _onlyPending = !_onlyPending),
          ),
        ],
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(e is AppException ? e.message : '$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (all) {
          final inventory = detail.value;
          final visible =
              _onlyPending ? all.where((i) => !i.isCounted).toList() : all;

          return Column(
            children: [
              if (inventory != null) ...[
                if (inventory.hasOverviewPhoto)
                  EvidenceBanner(
                    path: inventory.overviewPhotoUrl!,
                    caption: 'Vitrina · Inventario #${inventory.code}',
                  ),
                _Progress(inventory: inventory, items: all),
              ],
              const Divider(height: 1),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _onlyPending
                                ? 'No queda ningún producto por contar.'
                                : 'Esta jornada no tiene productos.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _ItemRow(
                          item: visible[i],
                          onTap: inventory == null || !inventory.isOpen
                              ? null
                              : () => _count(visible[i], inventory.standId),
                        ),
                      ),
              ),
              if (inventory != null && !inventory.isOpen)
                _ClosedSummary(inventory: inventory, items: all),
              if (inventory != null && inventory.isOpen)
                _CloseBar(
                  inventory: inventory,
                  items: all,
                  busy: _closing,
                  onAttachOverview: () => _attachOverview(inventory),
                  onFinalize: _finalize,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.inventory, required this.items});

  final Inventory inventory;
  final List<InventoryItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counted = items.where((i) => i.isCounted).length;
    final withDiff = items.where((i) => i.hasDifference).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${inventory.standName ?? ''} · '
                  '${Fmt.dateTime(inventory.startedAt)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              Text('$counted / ${items.length}',
                  style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: items.isEmpty ? 0 : counted / items.length,
              minHeight: 6,
            ),
          ),
          if (withDiff > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$withDiff producto(s) con diferencia',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final InventoryItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, color) = switch (item) {
      _ when !item.isCounted => (Icons.radio_button_unchecked, theme.colorScheme.outline),
      _ when item.hasDifference => (Icons.error, theme.colorScheme.error),
      _ => (Icons.check_circle, Colors.green.shade700),
    };

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(item.productName ?? 'Producto'),
      subtitle: Text(
        item.isCounted
            ? 'sistema ${item.systemQty} · contado ${item.countedQty}'
                '${item.hasPhoto ? ' · con foto' : ''}'
            : 'sistema ${item.systemQty} · sin contar',
        style: theme.textTheme.bodySmall,
      ),
      trailing: item.isCounted
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.hasPhoto) ...[
                  EvidenceThumb(
                    path: item.photoUrl!,
                    size: 44,
                    caption: item.productName,
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  Fmt.signed(item.difference),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ],
            )
          : const Icon(Icons.chevron_right),
    );
  }
}

/// Resumen de una jornada ya cerrada: qué se encontró y cómo quedó el stock.
class _ClosedSummary extends StatelessWidget {
  const _ClosedSummary({required this.inventory, required this.items});

  final Inventory inventory;
  final List<InventoryItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final withDiff = items.where((i) => i.hasDifference).toList();
    final net = withDiff.fold<int>(0, (sum, i) => sum + (i.difference ?? 0));

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(
                withDiff.isEmpty ? Icons.verified : Icons.rule,
                color: withDiff.isEmpty
                    ? Colors.green.shade700
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      withDiff.isEmpty
                          ? 'Cuadró sin diferencias'
                          : '${withDiff.length} diferencia(s) · neto ${Fmt.signed(net)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      'Cerrado ${Fmt.dateTime(inventory.completedAt)}'
                      '${inventory.profileName != null ? ' · ${inventory.profileName}' : ''}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra inferior de cierre: foto de vitrina y validaciones antes de finalizar.
class _CloseBar extends StatelessWidget {
  const _CloseBar({
    required this.inventory,
    required this.items,
    required this.busy,
    required this.onAttachOverview,
    required this.onFinalize,
  });

  final Inventory inventory;
  final List<InventoryItem> items;
  final bool busy;
  final VoidCallback onAttachOverview;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasOverview = inventory.hasOverviewPhoto;
    final counted = items.where((i) => i.isCounted).length;
    final missingPhotos =
        items.where((i) => i.hasDifference && !i.hasPhoto).length;

    // Las mismas condiciones que valida finalize_inventory() en la base.
    final blockers = <String>[
      if (counted == 0) 'Aún no has contado ningún producto',
      if (!hasOverview) 'Falta la fotografía general de la vitrina',
      if (missingPhotos > 0)
        '$missingPhotos producto(s) con diferencia sin fotografía',
    ];

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onAttachOverview,
                icon: Icon(hasOverview
                    ? Icons.photo_camera_back
                    : Icons.photo_camera_outlined),
                label: Text(hasOverview
                    ? 'Reemplazar foto de vitrina'
                    : 'Foto general de vitrina (obligatoria)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: hasOverview ? null : theme.colorScheme.error,
                  side: hasOverview
                      ? null
                      : BorderSide(color: theme.colorScheme.error),
                ),
              ),
              if (blockers.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final b in blockers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: theme.colorScheme.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(b,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline)),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 10),
              FilledButton(
                onPressed: busy || blockers.isNotEmpty ? null : onFinalize,
                child: busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cerrar jornada y cuadrar stock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
