import 'package:flutter/material.dart';

import '../../core/design/product_icons.dart';
import '../../core/design/tokens.dart';

/// Imagen de un producto, resuelta en cascada:
///
///   1. **foto propia** del producto, si la tiene
///   2. **icono elegido** para ese producto
///   3. **icono de su categoría**
///   4. **icono genérico**
///
/// La cascada vive aquí y no en cada pantalla: es la única forma de que la
/// tarjeta, el formulario y cualquier lista futura muestren siempre lo mismo.
/// Si la foto no carga —enlace roto, sin conexión— cae al icono en lugar de
/// dejar un hueco, porque en una rejilla el hueco blanco se lee como error.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({
    super.key,
    this.imageUrl,
    this.productIcon,
    this.categoryIcon,
    this.size = 40,
    this.iconSize,
  });

  final String? imageUrl;

  /// Icono elegido para este producto. Tiene prioridad sobre el de la categoría.
  final String? productIcon;

  /// Respaldo cuando el producto no tiene icono propio.
  final String? categoryIcon;

  final double size;
  final double? iconSize;

  bool get _hasPhoto => (imageUrl ?? '').trim().isNotEmpty;

  /// Primer identificador utilizable de la cascada.
  String? get _effectiveIcon {
    if (ProductIcons.isKnown(productIcon)) return productIcon;
    if (ProductIcons.isKnown(categoryIcon)) return categoryIcon;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size >= 64 ? Radii.md : Radii.sm);

    if (_hasPhoto) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Mientras carga se muestra el icono, no un hueco en blanco.
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _IconFallback(this),
          errorBuilder: (_, _, _) => _IconFallback(this),
        ),
      );
    }

    return _IconFallback(this);
  }
}

class _IconFallback extends StatelessWidget {
  const _IconFallback(this.avatar);

  final ProductAvatar avatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: avatar.size,
      height: avatar.size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius:
            BorderRadius.circular(avatar.size >= 64 ? Radii.md : Radii.sm),
      ),
      child: Icon(
        ProductIcons.resolve(avatar._effectiveIcon),
        size: avatar.iconSize ?? avatar.size * 0.55,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
