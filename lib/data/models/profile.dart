import '../../core/constants/enums.dart';

/// Usuario del sistema. Extiende `auth.users` de Supabase (tabla `profiles`).
class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.active,
    this.email,
    this.phone,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String? email;
  final UserRole role;
  final bool active;
  final String? phone;
  final DateTime? createdAt;

  bool get isAdmin => role.isAdmin;
  bool get isStaff => role.isStaff;

  String get displayName =>
      fullName.trim().isNotEmpty ? fullName.trim() : (email ?? 'Sin nombre');

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        fullName: (map['full_name'] as String?) ?? '',
        email: map['email'] as String?,
        role: UserRole.fromWire(map['role'] as String?),
        active: (map['active'] as bool?) ?? true,
        phone: map['phone'] as String?,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'role': role.wireValue,
        'active': active,
        'phone': phone,
      };

  Profile copyWith({String? fullName, UserRole? role, bool? active, String? phone}) =>
      Profile(
        id: id,
        fullName: fullName ?? this.fullName,
        email: email,
        role: role ?? this.role,
        active: active ?? this.active,
        phone: phone ?? this.phone,
        createdAt: createdAt,
      );
}
