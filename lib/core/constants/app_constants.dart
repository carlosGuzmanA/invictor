/// Nombres de tablas, vistas y funciones RPC de Supabase, en un solo lugar.
/// Evita literales sueltos repartidos por los servicios.
class Tables {
  const Tables._();

  static const profiles = 'profiles';
  static const categories = 'categories';
  static const stands = 'stands';
  static const userStands = 'user_stands';
  static const products = 'products';
  static const standProducts = 'stand_products';
  static const standStock = 'stand_stock';
  static const inventoryMovements = 'inventory_movements';
  static const inventories = 'inventories';
  static const inventoryItems = 'inventory_items';
  static const shipments = 'shipments';
  static const shipmentItems = 'shipment_items';
}

class Views {
  const Views._();

  static const productStock = 'v_product_stock';
  static const standStock = 'v_stand_stock';
  static const standCatalog = 'v_stand_catalog';
  static const inventorySummary = 'v_inventory_summary';
  static const shipments = 'v_shipments';
  static const shipmentItems = 'v_shipment_items';
}

class Rpc {
  const Rpc._();

  static const openInventory = 'open_inventory';
  static const finalizeInventory = 'finalize_inventory';
  static const rebuildStandStock = 'rebuild_stand_stock';
  static const receiveShipment = 'receive_shipment';
}

class AppConstants {
  const AppConstants._();

  static const appName = 'InVictor Inventario';

  /// Compresión de fotografías antes de subirlas (§18: reducir consumo de datos).
  static const photoMaxWidth = 1600.0;
  static const photoMaxHeight = 1600.0;
  static const photoQuality = 80;

  /// Límite del bucket en Supabase Storage: 8 MB.
  static const photoMaxBytes = 8 * 1024 * 1024;

  static const defaultPageSize = 50;
}
