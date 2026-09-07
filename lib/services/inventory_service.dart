import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/enums.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/formatters.dart';
import '../data/models/inventory.dart';
import '../data/models/inventory_item.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

/// Jornadas de inventario físico (§8): abrir, contar con foto, cerrar.
class InventoryService {
  const InventoryService({this.storage = const StorageService()});

  /// Inyectable para poder sustituirlo en tests.
  final StorageService storage;

  SupabaseClient get _db => SupabaseService.client;

  /// Abre una jornada y la precarga con los productos a contar (RPC).
  ///
  /// Por defecto carga el catálogo del puesto más lo que tenga saldo aunque no
  /// esté asignado. [fullCatalog] carga todos los productos activos del
  /// sistema: sirve para el inventario inicial de un puesto sin catálogo.
  ///
  /// La base impide tener dos inventarios abiertos en el mismo puesto.
  Future<String> openInventory({
    required String standId,
    bool fullCatalog = false,
  }) async {
    try {
      final id = await _db.rpc(Rpc.openInventory, params: {
        'p_stand_id': standId,
        'p_full_catalog': fullCatalog,
      });
      return id as String;
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<List<Inventory>> fetchInventories({
    String? standId,
    InventoryStatus? status,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    try {
      var query = _db.from(Views.inventorySummary).select();
      if (standId != null) query = query.eq('stand_id', standId);
      if (status != null) query = query.eq('status', status.wireValue);
      final rows = await query
          .order('started_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map<Inventory>((r) => Inventory.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Inventory?> fetchInventory(String id) async {
    try {
      final row = await _db
          .from(Views.inventorySummary)
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Inventory.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Inventario abierto del puesto, si existe.
  Future<Inventory?> fetchOpenInventory(String standId) async {
    try {
      final row = await _db
          .from(Views.inventorySummary)
          .select()
          .eq('stand_id', standId)
          .eq('status', InventoryStatus.abierto.wireValue)
          .maybeSingle();
      return row == null ? null : Inventory.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<List<InventoryItem>> fetchItems(
    String inventoryId, {
    bool onlyWithDifference = false,
  }) async {
    try {
      var query = _db
          .from(Tables.inventoryItems)
          .select('*, products(name, sku)')
          .eq('inventory_id', inventoryId);
      if (onlyWithDifference) query = query.neq('difference', 0);
      final rows = await query.order('created_at');
      return rows.map<InventoryItem>((r) => InventoryItem.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Registra el conteo físico de un producto.
  ///
  /// Sube la foto primero: si falla, el conteo no se guarda a medias.
  /// La foto es obligatoria únicamente donde el conteo difiere del sistema
  /// (§19); esa regla la aplica `finalize_inventory()` al cerrar.
  Future<InventoryItem> saveCount({
    required InventoryItem item,
    required String standId,
    required int countedQty,
    Uint8List? photoBytes,
    String photoContentType = 'image/jpeg',
    String? note,
  }) async {
    if (countedQty < 0) {
      throw const AppException('La cantidad contada no puede ser negativa.');
    }

    String? photoUrl = item.photoUrl;
    if (photoBytes != null) {
      final path = Fmt.photoPath(
        standId: standId,
        inventoryId: item.inventoryId,
        itemId: item.id,
        extension: photoContentType.endsWith('png') ? 'png' : 'jpg',
      );
      photoUrl = await storage.uploadPhoto(
        bytes: photoBytes,
        path: path,
        contentType: photoContentType,
      );
    }

    // Guardar un conteo sin foto está permitido: la regla es que la foto sea
    // obligatoria SOLO donde hay diferencia, y eso lo verifica
    // `finalize_inventory()` al cerrar la jornada (migración 0004). Bloquearlo
    // aquí impediría contar un producto que sí cuadra.

    try {
      final row = await _db
          .from(Tables.inventoryItems)
          .update({
            'counted_qty': countedQty,
            'photo_url': photoUrl,
            'note': note,
            'counted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', item.id)
          .select('*, products(name, sku)')
          .single();
      return InventoryItem.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Foto general de la vitrina/sector (§5), opcional.
  Future<void> saveOverviewPhoto({
    required String inventoryId,
    required String standId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final path = Fmt.photoPath(
      standId: standId,
      inventoryId: inventoryId,
      itemId: 'vitrina',
      extension: contentType.endsWith('png') ? 'png' : 'jpg',
    );
    final url = await storage.uploadPhoto(
      bytes: bytes,
      path: path,
      contentType: contentType,
    );
    try {
      await _db
          .from(Tables.inventories)
          .update({'overview_photo_url': url})
          .eq('id', inventoryId);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Cierra la jornada. La RPC valida las fotos y genera los ajustes de stock.
  Future<void> finalizeInventory(String inventoryId) async {
    try {
      await _db.rpc(Rpc.finalizeInventory, params: {
        'p_inventory_id': inventoryId,
      });
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<String> photoSignedUrl(String path) => storage.signedUrl(path);
}
