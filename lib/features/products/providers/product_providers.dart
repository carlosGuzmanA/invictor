import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/category.dart';
import '../../../data/models/product.dart';
import '../../../services/service_providers.dart';

/// Catálogo global con stock agregado, para la pantalla de administración.
/// Distinto de `activeStandCatalogProvider`, que es el catálogo de UN puesto.
final productsProvider =
    FutureProvider.autoDispose<List<Product>>((ref) async {
  return ref.watch(catalogServiceProvider).fetchProductsWithStock(limit: 200);
});

/// Categorías activas, para selectores y filtros.
final productCategoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(catalogServiceProvider).fetchCategories(),
);
