import '../../core/constants/enums.dart';

/// Cabecera de una jornada de inventario (§8).
///
/// Los contadores (`itemsTotal`, `itemsWithDifference`, ...) solo vienen
/// rellenos al leer desde la vista `v_inventory_summary`.
class Inventory {
  const Inventory({
    required this.id,
    required this.code,
    required this.standId,
    required this.status,
    required this.startedAt,
    this.profileId,
    this.note,
    this.overviewPhotoUrl,
    this.completedAt,
    this.standName,
    this.profileName,
    this.itemsTotal,
    this.itemsCounted,
    this.itemsOk,
    this.itemsWithDifference,
    this.netDifference,
    this.itemsMissingPhoto,
  });

  final String id;

  /// Número legible: "INVENTARIO #1045".
  final int code;
  final String standId;
  final String? profileId;
  final InventoryStatus status;
  final String? note;

  /// Foto general de la vitrina/sector (§5), independiente de la de cada producto.
  final String? overviewPhotoUrl;
  final DateTime startedAt;
  final DateTime? completedAt;

  final String? standName;
  final String? profileName;
  final int? itemsTotal;
  final int? itemsCounted;
  final int? itemsOk;
  final int? itemsWithDifference;
  final int? netDifference;

  /// Productos con diferencia y sin fotografía: bloquean el cierre (§19).
  /// Lo calcula `v_inventory_summary`.
  final int? itemsMissingPhoto;

  bool get isOpen => status.isOpen;

  bool get hasOverviewPhoto =>
      (overviewPhotoUrl ?? '').trim().isNotEmpty;

  double get progress => (itemsTotal ?? 0) == 0
      ? 0
      : (itemsCounted ?? 0) / (itemsTotal ?? 1);

  factory Inventory.fromMap(Map<String, dynamic> map) => Inventory(
        id: map['id'] as String,
        code: (map['code'] as num?)?.toInt() ?? 0,
        standId: map['stand_id'] as String,
        profileId: map['profile_id'] as String?,
        status: InventoryStatus.fromWire(map['status'] as String?),
        note: map['note'] as String?,
        overviewPhotoUrl: map['overview_photo_url'] as String?,
        startedAt: DateTime.tryParse(map['started_at']?.toString() ?? '') ??
            DateTime.now(),
        completedAt: DateTime.tryParse(map['completed_at']?.toString() ?? ''),
        standName: map['stand_name'] as String? ??
            (map['stands'] as Map<String, dynamic>?)?['name'] as String?,
        profileName: map['profile_name'] as String? ??
            (map['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
        itemsTotal: (map['items_total'] as num?)?.toInt(),
        itemsCounted: (map['items_counted'] as num?)?.toInt(),
        itemsOk: (map['items_ok'] as num?)?.toInt(),
        itemsWithDifference: (map['items_with_difference'] as num?)?.toInt(),
        netDifference: (map['net_difference'] as num?)?.toInt(),
        itemsMissingPhoto: (map['items_missing_photo'] as num?)?.toInt(),
      );
}
