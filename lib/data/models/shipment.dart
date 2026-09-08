import '../../core/constants/enums.dart';

/// Encomienda enviada a un puesto.
///
/// No hay bodega: el administrador compra la mercadería en Santiago y la
/// despacha en el momento. Al recibirla se generan movimientos de `entrada`,
/// porque es la primera vez que entra al sistema.
///
/// Los totales solo llegan al leer desde `v_shipments`; desde la tabla
/// `shipments` quedan en null.
class Shipment {
  const Shipment({
    required this.id,
    required this.toStandId,
    required this.status,
    required this.blind,
    required this.createdAt,
    this.standName,
    this.createdBy,
    this.createdByName,
    this.note,
    this.receivedAt,
    this.receivedBy,
    this.receivedByName,
    this.itemCount,
    this.sentTotal,
    this.receivedTotal,
    this.missingTotal,
  });

  final String id;
  final String toStandId;
  final String? standName;
  final ShipmentStatus status;

  /// true = el administrador no detalló el contenido.
  ///
  /// Es el caso real más común: manda el paquete y el vendedor descubre qué
  /// llegó. Cambia quién crea las líneas de la encomienda.
  final bool blind;

  final String? note;
  final DateTime createdAt;
  final String? createdBy;
  final String? createdByName;
  final DateTime? receivedAt;
  final String? receivedBy;
  final String? receivedByName;

  /// Solo desde `v_shipments`.
  final int? itemCount;
  final int? sentTotal;
  final int? receivedTotal;
  final int? missingTotal;

  /// El puesto todavía no la confirmó: es lo que el vendedor debe atender.
  bool get isPending => status.isPending;

  /// Llegó menos de lo que se despachó.
  ///
  /// Solo tiene sentido en una encomienda detallada: en una a ciegas no había
  /// cantidades declaradas contra las que comparar.
  bool get hasMissing => (missingTotal ?? 0) > 0;

  factory Shipment.fromMap(Map<String, dynamic> map) => Shipment(
        id: map['id'] as String,
        toStandId: map['to_stand_id'] as String,
        standName: map['stand_name'] as String?,
        status: ShipmentStatus.fromWire(map['status'] as String?),
        blind: (map['blind'] as bool?) ?? false,
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        createdBy: map['created_by'] as String?,
        createdByName: map['created_by_name'] as String?,
        receivedAt: map['received_at'] == null
            ? null
            : DateTime.parse(map['received_at'] as String),
        receivedBy: map['received_by'] as String?,
        receivedByName: map['received_by_name'] as String?,
        itemCount: (map['item_count'] as num?)?.toInt(),
        sentTotal: (map['sent_total'] as num?)?.toInt(),
        receivedTotal: (map['received_total'] as num?)?.toInt(),
        missingTotal: (map['missing_total'] as num?)?.toInt(),
      );

  /// `status`, `received_at` y `received_by` se omiten a propósito: los fija
  /// `receive_shipment()`. Enviarlos desde el cliente permitiría marcar una
  /// encomienda como recibida sin generar los movimientos de entrada, y el
  /// stock quedaría sin la mercadería que sí llegó.
  Map<String, dynamic> toInsertMap() => {
        'to_stand_id': toStandId,
        'created_by': createdBy,
        'blind': blind,
        'note': note,
      };
}
