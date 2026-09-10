import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../data/models/profile.dart';
import '../data/models/stand.dart';
import 'supabase_service.dart';

/// Autenticación y perfil del usuario actual.
class AuthService {
  const AuthService();

  SupabaseClient get _db => SupabaseService.client;

  Stream<AuthState> get onAuthStateChange =>
      SupabaseService.auth.onAuthStateChange;

  bool get isSignedIn => SupabaseService.isSignedIn;
  String? get currentUserId => SupabaseService.currentUserId;

  Future<Profile> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await SupabaseService.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.user == null) {
        throw const AppException('No fue posible iniciar sesión.');
      }
      final profile = await fetchCurrentProfile();
      if (profile == null) {
        await signOut();
        throw const AppException(
          'Tu cuenta no tiene un perfil asociado. Contacta al administrador.',
        );
      }
      if (!profile.active) {
        await signOut();
        throw const AppException('Tu cuenta está desactivada.');
      }
      return profile;
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<void> signOut() async {
    // Los canales de Realtime se cierran ANTES de cerrar sesión.
    //
    // El orden importa: `signOut` invalida el token y el websocket se cae con
    // él. Si la salida del canal de presencia sale después, ya no llega al
    // servidor y los demás siguen viendo al usuario conectado hasta que
    // expire el heartbeat.
    //
    // Va en su propio try: un fallo al cerrar un canal no debe dejar a nadie
    // atrapado dentro de la aplicación.
    try {
      await SupabaseService.client.removeAllChannels();
    } catch (_) {
      // Sin conexión o canal ya muerto: se continúa con el cierre de sesión.
    }

    try {
      await SupabaseService.auth.signOut();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await SupabaseService.auth.resetPasswordForEmail(email.trim());
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Cambia la contraseña de la sesión abierta.
  ///
  /// Recuperarla por correo obliga a salir de la aplicación, abrir el buzón y
  /// volver. Con la sesión ya iniciada eso sobra, y la fricción es justo lo
  /// que hace que nadie cambie una contraseña que el navegador lleva semanas
  /// señalando como filtrada.
  Future<void> changePassword(String newPassword) async {
    try {
      await SupabaseService.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      // Quitar la marca de contraseña temporal, si la había. Va después del
      // cambio y no antes: al revés, un fallo dejaría a la persona sin la
      // obligación de cambiar una contraseña que sigue siendo la vieja.
      //
      // Pasa por una función porque la policy impide a nadie borrarse la
      // marca a sí mismo — poder hacerlo sería poder saltarse el cambio.
      await SupabaseService.client.rpc(Rpc.setPasswordChanged);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Perfil del usuario autenticado, o null si no hay sesión.
  Future<Profile?> fetchCurrentProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    try {
      final row = await _db
          .from(Tables.profiles)
          .select()
          .eq('id', userId)
          .maybeSingle();
      return row == null ? null : Profile.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Puestos asignados al usuario (§19). Un admin/encargado ve todos.
  Future<List<Stand>> fetchAssignedStands(Profile profile) async {
    try {
      if (profile.isStaff) {
        final rows = await _db
            .from(Tables.stands)
            .select()
            .eq('active', true)
            .order('name');
        return rows.map<Stand>((r) => Stand.fromMap(r)).toList();
      }

      final rows = await _db
          .from(Tables.userStands)
          .select('stands(*)')
          .eq('profile_id', profile.id);

      return rows
          .map((r) => r['stands'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .map(Stand.fromMap)
          .where((s) => s.active)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Profile> updateOwnProfile({String? fullName, String? phone}) async {
    final userId = currentUserId;
    if (userId == null) throw const AppException('No hay sesión activa.');
    try {
      final row = await _db
          .from(Tables.profiles)
          .update({
            if (fullName != null) 'full_name': fullName.trim(),
            if (phone != null) 'phone': phone.trim(),
          })
          .eq('id', userId)
          .select()
          .single();
      return Profile.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }
}
