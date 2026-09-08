import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/enums.dart';
import '../core/errors/app_exception.dart';
import '../data/models/shipment.dart';
import '../data/models/shipment_item.dart';
import 'supabase_service.dart';

/// Encomiendas: cómo llega la mercadería a un puesto (0013).
///
/// El administrador compra en Santiago y despacha en el momento; no hay
/// bodega. Por eso recibir una encomienda genera movimientos de `entrada` y
/// no traslados — y por eso la recepción pasa siempre por la RPC, que hace
/// las tres cosas juntas: registra lo que llegó, lo añade al catálogo del
/// puesto y genera el movimiento.
class ShipmentService {
  const ShipmentService();

  SupabaseClient get _db => SupabaseService.client;

  /// Encomiendas visibles para el usuario. RLS ya limita a sus puestos.
  Future<List<Shipment>> fetchShipments({
    String? standId,
    ShipmentStatus? status,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    try {
      var query = _db.from(Views.shipments).select();
      if (standId != null) query = query.eq('to_stand_id', standId);
      if (status != null) query = query.eq('status', status.wireValue);

      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map<Shipment>((r) => Shipment.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<List<ShipmentItem>> fetchItems(String shipmentId) async {
    try {
      final rows = await _db
          .from(Views.shipmentItems)
          .select()
          .eq('shipment_id', shipmentId)
          .order('product_name');
      return rows.map<ShipmentItem>((r) => ShipmentItem.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Despacha una encomienda. Solo staff, y lo aplica RLS.
  ///
  /// Con [items] vacío queda a ciegas: el administrador declara que mandó un
  /// paquete y el contenido lo descubre el vendedor al abrirlo. Es el caso
  /// real más común, así que no es un error — pero `blind` tiene que decirlo
  /// explícitamente, porque una encomienda detallada sin líneas sí lo sería.
  Future<Shipment> createShipment({
    required String toStandId,
    required bool blind,
    String? note,
    List<ShipmentItem> items = const [],
  }) async {
    if (!blind && items.isEmpty) {
      throw const AppException(
        'Una encomienda detallada necesita al menos un producto. '
        'Si todavía no sabes qué mandas, márcala como encomienda a ciegas.',
      );
    }

    try {
      final row = await _db
          .from(Tables.shipments)
          .insert(
            Shipment(
              id: '',
              toStandId: toStandId,
              status: ShipmentStatus.enviado,
              blind: blind,
              note: note,
              createdAt: DateTime.now(),
              createdBy: SupabaseService.currentUserId,
            ).toInsertMap(),
          )
          .select()
          .single();

      final shipment = Shipment.fromMap(row);

      if (items.isNotEmpty) {
        await _db.from(Tables.shipmentItems).insert([
          for (final item in items)
            ShipmentItem(
              id: '',
              shipmentId: shipment.id,
              productId: item.productId,
              sentQty: item.sentQty,
              photoUrl: item.photoUrl,
            ).toInsertMap(),
        ]);
      }

      return shipment;
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Confirma lo que llegó al puesto.
  ///
  /// [received] es producto -> cantidad. Un 0 es válido y significativo: se
  /// esperaba el producto y no llegó nada, y eso queda como faltante de la
  /// encomienda sin generar ningún movimiento — lo que no llegó nunca estuvo
  /// en el puesto.
  Future<void> receiveShipment({
    required String shipmentId,
    required Map<String, int> received,
    Map<String, String> photos = const {},
  }) async {
    if (received.isEmpty) {
      throw const AppException(
        'No hay nada que recibir: registra al menos un producto.',
      );
    }

    try {
      await _db.rpc(Rpc.receiveShipment, params: {
        'p_shipment_id': shipmentId,
        'p_items': [
          for (final entry in received.entries)
            {
              'product_id': entry.key,
              'received_qty': entry.value,
              'photo_url': photos[entry.key],
            },
        ],
      });
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Anula una encomienda que se despachó por error o que no llegó nunca.
  ///
  /// No se borra: una encomienda perdida es justo lo que hay que poder
  /// consultar después.
  Future<void> cancelShipment(String shipmentId) async {
    try {
      await _db
          .from(Tables.shipments)
          .update({'status': ShipmentStatus.anulado.wireValue})
          .eq('id', shipmentId);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Productos que un vendedor registró sin saber el precio.
  ///
  /// Es la lista que el administrador tiene que completar; sin ella, un
  /// producto sin precio se pierde en el catálogo y nadie lo confirma.
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
}
