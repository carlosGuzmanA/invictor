import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/enums.dart';
import '../core/errors/app_exception.dart';
import '../data/models/inventory_movement.dart';
import '../data/models/stand_stock.dart';
import 'supabase_service.dart';

/// Registro de movimientos y consulta de stock por puesto.
///
/// El stock NO se escribe: se escribe un movimiento y el trigger de la base
/// actualiza `stand_stock`. Así el saldo siempre es reconstruible (§6).
class MovementService {
  const MovementService();

  SupabaseClient get _db => SupabaseService.client;

  /// Registro rápido de salida (§4.1): el caso de uso más frecuente.
  Future<InventoryMovement> registerExit({
    required String productId,
    required String standId,
    int quantity = 1,
    String? note,
  }) =>
      registerMovement(
        productId: productId,
        standId: standId,
        type: MovementType.salida,
        quantity: quantity,
        note: note,
      );

  /// Anula un movimiento recién registrado con otro que lo compensa.
  ///
  /// No lo borra: los movimientos son inmutables (§19). Un descuento por error
  /// deja dos líneas en el historial —la salida y su devolución— porque eso es
  /// lo que de verdad ocurrió. Perder el rastro sería peor que el ruido.
  ///
  /// Un vendedor puede compensar una `salida` con una `devolucion`, ambas
  /// operativas. Compensar un ajuste requiere ser staff, y lo aplica RLS.
  Future<InventoryMovement> compensate(InventoryMovement original) {
    final opposite = switch (original.type) {
      MovementType.salida => MovementType.devolucion,
      MovementType.devolucion => MovementType.salida,
      MovementType.entrada => MovementType.ajusteNegativo,
      MovementType.ajustePositivo => MovementType.ajusteNegativo,
      MovementType.ajusteNegativo => MovementType.ajustePositivo,
      MovementType.trasladoEntrada => MovementType.trasladoSalida,
      MovementType.trasladoSalida => MovementType.trasladoEntrada,
    };

    return registerMovement(
      productId: original.productId,
      standId: original.standId,
      type: opposite,
      quantity: original.quantity,
      note: 'Corrección de un registro anterior',
    );
  }

  Future<InventoryMovement> registerMovement({
    required String productId,
    required String standId,
    required MovementType type,
    required int quantity,
    String? note,
    String? inventoryId,
  }) async {
    if (quantity <= 0) {
      throw const AppException('La cantidad debe ser mayor que 0.');
    }
    try {
      final movement = InventoryMovement(
        id: '',
        productId: productId,
        standId: standId,
        profileId: SupabaseService.currentUserId,
        type: type,
        quantity: quantity,
        note: note,
        inventoryId: inventoryId,
        createdAt: DateTime.now(),
      );
      final row = await _db
          .from(Tables.inventoryMovements)
          .insert(movement.toInsertMap())
          .select()
          .single();
      return InventoryMovement.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Traslado entre puestos: dos movimientos unidos por `transfer_group_id`.
  Future<void> registerTransfer({
    required String productId,
    required String fromStandId,
    required String toStandId,
    required int quantity,
    String? note,
  }) async {
    if (fromStandId == toStandId) {
      throw const AppException('El puesto de origen y destino son el mismo.');
    }
    if (quantity <= 0) {
      throw const AppException('La cantidad debe ser mayor que 0.');
    }
    final groupId = const Uuid().v4();
    final userId = SupabaseService.currentUserId;
    try {
      await _db.from(Tables.inventoryMovements).insert([
        {
          'product_id': productId,
          'stand_id': fromStandId,
          'profile_id': userId,
          'type': MovementType.trasladoSalida.wireValue,
          'quantity': quantity,
          'transfer_group_id': groupId,
          'counterpart_stand_id': toStandId,
          'note': ?note,
        },
        {
          'product_id': productId,
          'stand_id': toStandId,
          'profile_id': userId,
          'type': MovementType.trasladoEntrada.wireValue,
          'quantity': quantity,
          'transfer_group_id': groupId,
          'counterpart_stand_id': fromStandId,
          'note': ?note,
        },
      ]);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Historial de movimientos con filtros (§10).
  Future<List<InventoryMovement>> fetchMovements({
    String? standId,
    String? productId,
    String? profileId,
    MovementType? type,
    DateTime? from,
    DateTime? to,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    try {
      // `stands!stand_id` es obligatorio, no cosmético: inventory_movements
      // tiene DOS claves foráneas a stands (stand_id y counterpart_stand_id)
      // y sin desambiguar PostgREST rechaza la consulta con PGRST201.
      var query = _db.from(Tables.inventoryMovements).select(
            '*, products(name, sku), stands!stand_id(name), profiles(full_name)',
          );
      if (standId != null) query = query.eq('stand_id', standId);
      if (productId != null) query = query.eq('product_id', productId);
      if (profileId != null) query = query.eq('profile_id', profileId);
      if (type != null) query = query.eq('type', type.wireValue);
      if (from != null) query = query.gte('created_at', from.toIso8601String());
      if (to != null) query = query.lte('created_at', to.toIso8601String());

      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map<InventoryMovement>((r) => InventoryMovement.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Stock de un puesto (vista `v_stand_stock`).
  Future<List<StandStock>> fetchStandStock(
    String standId, {
    bool onlyLow = false,
  }) async {
    try {
      var query = _db.from(Views.standStock).select().eq('stand_id', standId);
      if (onlyLow) query = query.eq('low_stock', true);
      final rows = await query.order('product_name');
      return rows.map<StandStock>((r) => StandStock.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Stock de un producto concreto en un puesto. 0 si nunca hubo movimientos.
  Future<int> stockFor({
    required String productId,
    required String standId,
  }) async {
    try {
      final row = await _db
          .from(Tables.standStock)
          .select('quantity')
          .eq('product_id', productId)
          .eq('stand_id', standId)
          .maybeSingle();
      return (row?['quantity'] as num?)?.toInt() ?? 0;
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Movimientos en vivo de un puesto (Realtime, §11).
  Stream<List<InventoryMovement>> watchMovements(String standId) => _db
      .from(Tables.inventoryMovements)
      .stream(primaryKey: ['id'])
      .eq('stand_id', standId)
      .order('created_at', ascending: false)
      .limit(AppConstants.defaultPageSize)
      .map((rows) => rows.map(InventoryMovement.fromMap).toList());
}
