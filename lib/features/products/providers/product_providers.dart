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

/// Cuántos productos esperan que alguien confirme su precio.
///
/// Un vendedor puede registrar lo que le llegó sin saber cuánto vale. Ese
/// producto se vendería a cero si nadie lo completa, así que hace falta que
/// el aviso salga a buscar a quien puede arreglarlo, y no al revés.
final pendingPriceCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(catalogServiceProvider).pendingPriceCount(),
);

/// Los productos que están esperando precio.
final pendingPriceProductsProvider =
    FutureProvider.autoDispose<List<Product>>(
  (ref) => ref.watch(catalogServiceProvider).fetchPendingPriceProducts(),
);

/// Categorías activas, para selectores y filtros.
final productCategoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(catalogServiceProvider).fetchCategories(),
);
