import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/product_icons.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/product.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/photo_service.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../providers/product_providers.dart';
import 'icon_picker_sheet.dart';

/// Crear o editar un producto. Solo encargado/admin, y lo aplica RLS.
///
/// La imagen sigue la cascada del catálogo: si no se sube foto, el producto
/// muestra el icono de su categoría. Por eso el selector de categoría enseña
/// el icono que heredaría — se ve el resultado antes de guardar.
class ProductFormSheet extends ConsumerStatefulWidget {
  const ProductFormSheet({super.key, this.product, this.standId});

  /// null = crear uno nuevo.
  final Product? product;

  /// Puesto desde el que se está creando. Un producto nuevo se asigna a él
  /// automáticamente: sin eso no aparecería en ninguna pantalla, porque
  /// `v_stand_catalog` solo muestra lo asignado al puesto o con saldo.
  final String? standId;

  static Future<bool> show(
    BuildContext context, {
    Product? product,
    String? standId,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProductFormSheet(product: product, standId: standId),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final _nameCtrl = TextEditingController(text: _p?.name ?? '');
  late final _skuCtrl = TextEditingController(text: _p?.sku ?? '');
  late final _priceCtrl = TextEditingController(
    text: _p?.price == null ? '' : _fmtPrice(_p!.price),
  );
  late final _minStockCtrl = TextEditingController(
    text: (_p?.minStock ?? 0).toString(),
  );

  String? _categoryId;
  String? _iconId;
  CapturedPhoto? _newPhoto;
  bool _removePhoto = false;
  bool _busy = false;
  String? _error;

  Product? get _p => widget.product;
  bool get _isNew => _p == null;

  static String _fmtPrice(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// Qué nivel de la cascada se está mostrando ahora mismo.
  String _imageSourceLabel(String? currentImage, String? categoryIcon) {
    if (_newPhoto != null || (currentImage ?? '').isNotEmpty) {
      return 'Foto del producto';
    }
    if (ProductIcons.isKnown(_iconId)) return 'Icono elegido';
    if (ProductIcons.isKnown(categoryIcon)) return 'Icono de la categoría';
    return 'Icono genérico';
  }

  @override
  void initState() {
    super.initState();
    _categoryId = _p?.categoryId;
    _iconId = _p?.icon;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _priceCtrl.dispose();
    _minStockCtrl.dispose();
    super.dispose();
  }

  /// Opciones de imagen, abiertas desde el propio avatar.
  Future<void> _showImageOptions() async {
    final hasPhoto =
        _newPhoto != null || (!_removePhoto && (_p?.imageUrl ?? '').isNotEmpty);

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(ProductIcons.resolve(_iconId)),
              title: const Text('Elegir icono'),
              subtitle: Text(
                ProductIcons.labelOf(_iconId) ?? 'De la lista precargada',
              ),
              onTap: () => Navigator.pop(ctx, 'icono'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar fotografía'),
              subtitle: const Text('Con la cámara del dispositivo'),
              onTap: () => Navigator.pop(ctx, 'camara'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Subir imagen'),
              subtitle: const Text('Desde los archivos del dispositivo'),
              onTap: () => Navigator.pop(ctx, 'galeria'),
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  'Quitar fotografía',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                subtitle: const Text('Vuelve a mostrarse el icono'),
                onTap: () => Navigator.pop(ctx, 'quitar'),
              ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;
    switch (action) {
      case 'icono':
        await _pickIcon();
      case 'camara':
        await _pickPhoto(ImageSource.camera);
      case 'galeria':
        await _pickPhoto(ImageSource.gallery);
      case 'quitar':
        setState(() {
          _newPhoto = null;
          _removePhoto = true;
        });
    }
  }

  Future<void> _pickIcon() async {
    final chosen = await IconPickerSheet.show(context, selected: _iconId);
    if (chosen == null || !mounted) return;
    // '' = el usuario quitó el icono; vuelve a heredar el de la categoría.
    setState(() => _iconId = chosen.isEmpty ? null : chosen);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => _error = null);
    try {
      final photo = await ref
          .read(photoServiceProvider)
          .capture(source: source);
      if (photo == null) return; // cancelado, no es error
      if (mounted) {
        setState(() {
          _newPhoto = photo;
          _removePhoto = false;
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final catalog = ref.read(catalogServiceProvider);
      final price =
          double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      final minStock = int.tryParse(_minStockCtrl.text.trim()) ?? 0;
      final sku = _skuCtrl.text.trim();

      // Al crear hace falta el id antes de poder subir la foto, porque la ruta
      // en Storage se nombra con él. Se guarda primero y se actualiza después.
      var saved = _isNew
          ? await catalog.createProduct(
              Product(
                id: '',
                name: _nameCtrl.text.trim(),
                sku: sku.isEmpty ? null : sku,
                categoryId: _categoryId,
                price: price,
                minStock: minStock,
                icon: _iconId,
                active: true,
              ),
            )
          : await catalog.updateProduct(
              _p!.copyWith(
                name: _nameCtrl.text.trim(),
                sku: sku.isEmpty ? null : sku,
                categoryId: _categoryId,
                price: price,
                minStock: minStock,
                icon: _iconId ?? '',
                imageUrl: _removePhoto ? '' : _p!.imageUrl,
              ),
            );

      if (_newPhoto != null) {
        final url = await ref
            .read(storageServiceProvider)
            .uploadProductPhoto(
              bytes: _newPhoto!.bytes,
              productId: saved.id,
              contentType: _newPhoto!.contentType,
            );
        saved = await catalog.updateProduct(saved.copyWith(imageUrl: url));
      } else if (_removePhoto && !_isNew) {
        await ref.read(storageServiceProvider).removeProductPhoto(saved.id);
      }

      // Un producto recién creado no pertenece a ningún puesto, y la vista
      // del catálogo solo muestra lo asignado o con saldo: sin esto, el
      // producto quedaría guardado pero invisible.
      if (_isNew && widget.standId != null) {
        await catalog.assignProductsToStand(
          standId: widget.standId!,
          productIds: [saved.id],
        );
      }

      if (!mounted) return;
      ref.invalidate(productsProvider);
      Navigator.of(context).pop(true);
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
    final categories = ref.watch(productCategoriesProvider);
    final selected = categories.value
        ?.where((c) => c.id == _categoryId)
        .firstOrNull;

    final currentImage = _removePhoto ? null : _p?.imageUrl;

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
                _isNew ? 'Nuevo producto' : 'Editar producto',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Space.xl),

              // El avatar ES el control: tocarlo abre las opciones. Tres
              // botones ocupaban más de lo que valían en una hoja donde lo
              // importante es el formulario.
              Row(
                children: [
                  _AvatarButton(
                    onTap: _busy ? null : _showImageOptions,
                    child: _newPhoto != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(Radii.md),
                            child: Image.memory(
                              _newPhoto!.bytes,
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                            ),
                          )
                        : ProductAvatar(
                            imageUrl: currentImage,
                            productIcon: _iconId,
                            categoryIcon: selected?.icon,
                            size: 76,
                          ),
                  ),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _imageSourceLabel(currentImage, selected?.icon),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Toca la imagen para cambiarla',
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

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _skuCtrl,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Código / SKU',
                        hintText: 'opcional',
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: TextFormField(
                      controller: _priceCtrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Precio',
                        prefixText: r'$ ',
                      ),
                      validator: Validators.price,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),

              categories.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(
                  'No se pudieron cargar las categorías',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                data: (list) => DropdownButtonFormField<String?>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Sin categoría'),
                    ),
                    for (final c in list)
                      DropdownMenuItem(
                        value: c.id,
                        child: Row(
                          children: [
                            Icon(ProductIcons.resolve(c.icon), size: 18),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _categoryId = v),
                ),
              ),
              const SizedBox(height: Space.md),

              TextFormField(
                controller: _minStockCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Stock mínimo',
                  helperText: 'Avisa cuando el stock baje a este valor',
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: Space.md),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],

              const SizedBox(height: Space.xl),
              BusyButton(
                label: _isNew ? 'Crear producto' : 'Guardar cambios',
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

/// Envuelve el avatar para que se lea como un control: superpone un lápiz y
/// responde al toque. Sin esa señal, nadie descubre que la imagen es pulsable.
class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
              child: Icon(
                Icons.edit,
                size: 12,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
