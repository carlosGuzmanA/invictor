import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/size_templates.dart';
import '../core/errors/app_exception.dart';
import '../data/models/category.dart';
import '../data/models/product.dart';
import '../data/models/stand.dart';
import '../data/models/stand_catalog_item.dart';
import 'supabase_service.dart';

/// CRUD del catálogo: categorías, productos y puestos.
/// Escritura restringida por RLS (staff para catálogo, admin para puestos).
class CatalogService {
  const CatalogService();

  SupabaseClient get _db => SupabaseService.client;

  // ---------------------------------------------------------------- Categorías

  Future<List<Category>> fetchCategories({bool onlyActive = true}) async {
    try {
      var query = _db.from(Tables.categories).select();
      if (onlyActive) query = query.eq('active', true);
      final rows = await query.order('name');
      return rows.map<Category>((r) => Category.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Category> createCategory(Category category) async {
    try {
      final row = await _db
          .from(Tables.categories)
          .insert(category.toInsertMap())
          .select()
          .single();
      return Category.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Category> updateCategory(Category category) async {
    try {
      final row = await _db
          .from(Tables.categories)
          .update(category.toInsertMap())
          .eq('id', category.id)
          .select()
          .single();
      return Category.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  // ---------------------------------------------------------------- Productos

  /// Catálogo con stock global agregado (vista `v_product_stock`).
  Future<List<Product>> fetchProductsWithStock({
    String? search,
    String? categoryId,
    bool onlyActive = true,
    bool onlyLowStock = false,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    try {
      var query = _db.from(Views.productStock).select();
      if (onlyActive) query = query.eq('active', true);
      if (categoryId != null) query = query.eq('category_id', categoryId);
      if (onlyLowStock) query = query.eq('low_stock', true);
      if (search != null && search.trim().isNotEmpty) {
        final term = '%${search.trim()}%';
        query = query.or('name.ilike.$term,sku.ilike.$term');
      }
      final rows = await query.order('name').range(offset, offset + limit - 1);
      return rows.map<Product>((r) => Product.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Product?> fetchProduct(String id) async {
    try {
      final row = await _db
          .from(Tables.products)
          .select('*, categories(name)')
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Product.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Product> createProduct(Product product) async {
    try {
      final row = await _db
          .from(Tables.products)
          .insert(product.toInsertMap())
          .select()
          .single();
      return Product.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Product> updateProduct(Product product) async {
    try {
      final row = await _db
          .from(Tables.products)
          .update(product.toInsertMap())
          .eq('id', product.id)
          .select()
          .single();
      return Product.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Crea un modelo con todas sus tallas de una vez.
  ///
  /// El modelo padre lleva el nombre, la categoría y la fotografía; cada talla
  /// es un producto con su propio stock y su propio precio, que es lo que en
  /// realidad se vende. El padre no se asigna a ningún puesto: la vista lo
  /// excluye del catálogo para que nadie descuente de él.
  ///
  /// Devuelve el modelo creado. Si falla a mitad se borra lo hecho: un modelo
  /// sin tallas no aparecería en ninguna pantalla —la vista lo oculta— y se
  /// quedaría ahí, invisible, ocupando el nombre.
  Future<Product> createProductWithSizes({
    required Product model,
    required List<SizeChoice> sizes,
    required Map<PriceBand, double> prices,
    String? standId,
  }) async {
    if (sizes.isEmpty) {
      throw const AppException('Elige al menos una talla.');
    }

    Product? parent;
    try {
      parent = await createProduct(model);

      final rows = [
        for (final size in sizes)
          Product(
            id: '',
            name: '${model.name} ${size.label}',
            sku: null,
            categoryId: model.categoryId,
            price: prices[size.band] ?? 0,
            // Sin precio no se confirma: sale marcado para completarlo.
            priceConfirmed: (prices[size.band] ?? 0) > 0,
            minStock: model.minStock,
            icon: model.icon,
            active: true,
            parentId: parent.id,
            variantLabel: size.label,
            variantOrder: size.order,
          ).toInsertMap(),
      ];

      final created = await _db.from(Tables.products).insert(rows).select();

      if (standId != null) {
        await assignProductsToStand(
          standId: standId,
          productIds: created.map<String>((r) => r['id'] as String).toList(),
        );
      }

      return parent;
    } catch (e, s) {
      // Deshacer: al borrar el padre, las tallas caen con él por la clave
      // foránea en cascada.
      if (parent != null) {
        try {
          await _db.from(Tables.products).delete().eq('id', parent.id);
        } catch (_) {
          // Si tampoco se puede deshacer, el error original es el que
          // importa: taparlo con este dejaría sin pista de qué pasó.
        }
      }
      throw mapError(e, s);
    }
  }

  /// Las tallas de un modelo, en su orden de presentación.
  Future<List<Product>> fetchVariants(String parentId) async {
    try {
      final rows = await _db
          .from(Tables.products)
          .select()
          .eq('parent_id', parentId)
          .eq('active', true)
          .order('variant_order');
      return rows.map<Product>((r) => Product.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Cuántos productos esperan que alguien confirme su precio.
  ///
  /// Un vendedor puede registrar lo que le llegó sin saber cuánto vale
  /// (migración 0013). Ese producto se vendería a cero si nadie lo completa,
  /// así que hace falta un contador que lo saque de entre los demás.
  Future<int> pendingPriceCount() async {
    try {
      final rows = await _db
          .from(Tables.products)
          .select('id')
          .eq('price_confirmed', false)
          .eq('active', true);
      return rows.length;
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Los productos que están esperando precio, para poder completarlos.
  Future<List<Product>> fetchPendingPriceProducts() async {
    try {
      final rows = await _db
          .from(Tables.products)
          .select('*, categories(name)')
          .eq('price_confirmed', false)
          .eq('active', true)
          .order('created_at');
      return rows.map<Product>((r) => Product.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Elimina un producto, con sus tallas si las tiene.
  ///
  /// La base decide qué significa «eliminar»: si nunca se movió lo borra de
  /// verdad —fue un error de tecleo—, y si tiene historial lo desactiva,
  /// porque borrarlo dejaría ventas apuntando a un producto inexistente.
  ///
  /// Devuelve `'borrado'` o `'desactivado'` para poder decírselo a quien lo
  /// pidió: no es lo mismo, y quien lo hace tiene que saber cuál de las dos
  /// ocurrió.
  Future<String> removeProduct(String productId) async {
    try {
      final res = await _db.rpc(Rpc.removeProduct, params: {
        'p_product_id': productId,
      });
      return res as String;
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Los productos no se eliminan: se desactivan, para no romper el historial.
  Future<void> deactivateProduct(String id) async {
    try {
      await _db.from(Tables.products).update({'active': false}).eq('id', id);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  // ------------------------------------------------------- Catálogo por puesto

  /// Productos operables en un puesto: los asignados MÁS los que tengan saldo
  /// aunque no lo estén (llegados por traslado). Alimenta la salida rápida.
  Future<List<StandCatalogItem>> fetchStandCatalog(
    String standId, {
    String? search,
    String? categoryId,
    bool onlyWithStock = false,
    bool onlyLowStock = false,
  }) async {
    try {
      var query =
          _db.from(Views.standCatalog).select().eq('stand_id', standId);
      if (categoryId != null) query = query.eq('category_id', categoryId);
      if (onlyLowStock) query = query.eq('low_stock', true);
      if (onlyWithStock) query = query.gt('quantity', 0);
      if (search != null && search.trim().isNotEmpty) {
        final term = '%${search.trim()}%';
        query = query.or('product_name.ilike.$term,sku.ilike.$term');
      }
      final rows = await query.order('product_name');
      return rows
          .map<StandCatalogItem>((r) => StandCatalogItem.fromMap(r))
          .toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Asigna productos a un puesto. Solo staff (lo aplica RLS).
  Future<void> assignProductsToStand({
    required String standId,
    required List<String> productIds,
  }) async {
    if (productIds.isEmpty) return;
    try {
      await _db.from(Tables.standProducts).upsert(
            [
              for (final id in productIds)
                {'stand_id': standId, 'product_id': id, 'active': true},
            ],
            onConflict: 'stand_id,product_id',
          );
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Quita un producto del catálogo de un puesto.
  ///
  /// No borra existencias: si quedaba saldo, sigue apareciendo en
  /// `v_stand_catalog` marcado como fuera de catálogo.
  Future<void> removeProductFromStand({
    required String standId,
    required String productId,
  }) async {
    try {
      await _db
          .from(Tables.standProducts)
          .delete()
          .eq('stand_id', standId)
          .eq('product_id', productId);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  // ------------------------------------------------------------------ Puestos

  Future<List<Stand>> fetchStands({bool onlyActive = true}) async {
    try {
      var query = _db.from(Tables.stands).select();
      if (onlyActive) query = query.eq('active', true);
      final rows = await query.order('name');
      return rows.map<Stand>((r) => Stand.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Stand> createStand(Stand stand) async {
    try {
      final row = await _db
          .from(Tables.stands)
          .insert(stand.toInsertMap())
          .select()
          .single();
      return Stand.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Stand> updateStand(Stand stand) async {
    try {
      final row = await _db
          .from(Tables.stands)
          .update(stand.toInsertMap())
          .eq('id', stand.id)
          .select()
          .single();
      return Stand.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }
}
