import '../../core/constants/enums.dart';

/// Puesto, carrito o bodega. Toda existencia física pertenece a un stand.
class Stand {
  const Stand({
    required this.id,
    required this.name,
    required this.type,
    required this.active,
    this.location,
  });

  final String id;
  final String name;
  final String? location;
  final StandType type;
  final bool active;

  bool get isWarehouse => type == StandType.bodega;

  factory Stand.fromMap(Map<String, dynamic> map) => Stand(
        id: map['id'] as String,
        name: map['name'] as String,
        location: map['location'] as String?,
        type: StandType.fromWire(map['type'] as String?),
        active: (map['active'] as bool?) ?? true,
      );

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'location': location,
        'type': type.wireValue,
        'active': active,
      };

  Stand copyWith({String? name, String? location, StandType? type, bool? active}) =>
      Stand(
        id: id,
        name: name ?? this.name,
        location: location ?? this.location,
        type: type ?? this.type,
        active: active ?? this.active,
      );
}
