import '../../core/constants/enums.dart';

/// Usuario del sistema. Extiende `auth.users` de Supabase (tabla `profiles`).
class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.active,
    this.mustChangePassword = false,
    this.email,
    this.phone,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String? email;
  final UserRole role;
  final bool active;

  /// Tiene puesta una contraseña temporal que fijó un administrador.
  ///
  /// Se dicta de viva voz porque los vendedores se dan de alta con correos
  /// inventados y el enlace de restablecimiento no llega a ninguna parte. Sin
  /// obligar a cambiarla, esa clave —que el administrador conoce y que
  /// cualquiera pudo oír— se quedaría puesta indefinidamente, y con ella se
  /// registran salidas que el historial atribuye a esta persona.
  final bool mustChangePassword;
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
        mustChangePassword:
            (map['must_change_password'] as bool?) ?? false,
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

  Profile copyWith({
    String? fullName,
    UserRole? role,
    bool? active,
    String? phone,
    bool? mustChangePassword,
  }) =>
      Profile(
        id: id,
        fullName: fullName ?? this.fullName,
        email: email,
        role: role ?? this.role,
        active: active ?? this.active,
        mustChangePassword:
            mustChangePassword ?? this.mustChangePassword,
        phone: phone ?? this.phone,
        createdAt: createdAt,
      );
}
