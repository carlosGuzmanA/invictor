import '../../core/constants/enums.dart';

/// Evento de inventario. Es la fuente única de verdad del stock (§6).
///
/// [quantity] es SIEMPRE positiva; el signo lo aporta [type].
/// [signedQuantity] lo calcula PostgreSQL como columna generada.
class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.standId,
    required this.type,
    required this.quantity,
    required this.createdAt,
    this.signedQuantity,
    this.profileId,
    this.note,
    this.transferGroupId,
    this.counterpartStandId,
    this.inventoryId,
    this.productName,
    this.standName,
    this.profileName,
  });

  final String id;
  final String productId;
  final String standId;
  final String? profileId;
  final MovementType type;
  final int quantity;
  final int? signedQuantity;
  final String? note;
  final String? transferGroupId;
  final String? counterpartStandId;
  final String? inventoryId;
  final DateTime createdAt;

  // Campos desnormalizados que llegan de un join, para listados.
  final String? productName;
  final String? standName;
  final String? profileName;

  int get effectiveQuantity => signedQuantity ?? quantity * type.sign;

  factory InventoryMovement.fromMap(Map<String, dynamic> map) =>
      InventoryMovement(
        id: map['id'] as String,
        productId: map['product_id'] as String,
        standId: map['stand_id'] as String,
        profileId: map['profile_id'] as String?,
        type: MovementType.fromWire(map['type'] as String?),
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        signedQuantity: (map['signed_quantity'] as num?)?.toInt(),
        note: map['note'] as String?,
        transferGroupId: map['transfer_group_id'] as String?,
        counterpartStandId: map['counterpart_stand_id'] as String?,
        inventoryId: map['inventory_id'] as String?,
        createdAt:
            DateTime.tryParse(map['created_at']?.toString() ?? '') ??
                DateTime.now(),
        productName:
            (map['products'] as Map<String, dynamic>?)?['name'] as String?,
        standName:
            (map['stands'] as Map<String, dynamic>?)?['name'] as String?,
        profileName:
            (map['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
      );

  /// `signed_quantity` e `id` los genera la base: no se envían.
  Map<String, dynamic> toInsertMap() => {
        'product_id': productId,
        'stand_id': standId,
        if (profileId != null) 'profile_id': profileId,
        'type': type.wireValue,
        'quantity': quantity,
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
        if (transferGroupId != null) 'transfer_group_id': transferGroupId,
        if (counterpartStandId != null)
          'counterpart_stand_id': counterpartStandId,
        if (inventoryId != null) 'inventory_id': inventoryId,
      };
}
