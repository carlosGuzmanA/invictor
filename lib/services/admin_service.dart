import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/enums.dart';
import '../core/errors/app_exception.dart';
import '../data/models/audit_entry.dart';
import '../data/models/profile.dart';
import '../data/models/stand.dart';
import 'supabase_service.dart';

/// Gestión de usuarios y sus asignaciones a puestos.
///
/// El **alta** de usuarios no está aquí a propósito: crearlos requiere la
/// service_role key, que nunca debe viajar al navegador. Se hacen desde
/// Supabase Auth y esta pantalla les asigna rol y puestos.
///
/// Cambiar roles y asignaciones es exclusivo de admin, y lo aplica RLS
/// (`profiles_admin_all`, `user_stands_write`): la interfaz solo evita el
/// intento fallido.
class AdminService {
  const AdminService();

  SupabaseClient get _db => SupabaseService.client;

  Future<List<Profile>> fetchProfiles({bool includeInactive = true}) async {
    try {
      var query = _db.from(Tables.profiles).select();
      if (!includeInactive) query = query.eq('active', true);
      final rows = await query.order('full_name');
      return rows.map<Profile>((r) => Profile.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Profile> updateRole(String profileId, UserRole role) async {
    try {
      final row = await _db
          .from(Tables.profiles)
          .update({'role': role.wireValue})
          .eq('id', profileId)
          .select()
          .single();
      return Profile.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Desactivar en vez de eliminar: borrar un perfil dejaría sin autor los
  /// movimientos que registró, y el historial debe seguir siendo auditable.
  Future<Profile> setActive(String profileId, bool active) async {
    try {
      final row = await _db
          .from(Tables.profiles)
          .update({'active': active})
          .eq('id', profileId)
          .select()
          .single();
      return Profile.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// Fija una contraseña temporal a otro usuario.
  ///
  /// Pasa por una Edge Function porque cambiar la contraseña de otra persona
  /// exige la clave de servicio, que jamás puede viajar al navegador: quien
  /// la tuviera se saltaría RLS entero. La función comprueba por su cuenta
  /// que quien llama es administrador — que el botón solo salga en su
  /// pantalla no impide llamar a la URL a mano con otro token.
  ///
  /// Deja al usuario obligado a cambiarla al entrar. Una clave dictada de
  /// viva voz no identifica a nadie: cualquiera que la oyera puede operar en
  /// su nombre, y el historial lo atribuirá a él.
  Future<String?> setTemporaryPassword({
    required String profileId,
    required String password,
  }) async {
    try {
      final res = await SupabaseService.client.functions.invoke(
        'admin-set-password',
        body: {'user_id': profileId, 'password': password},
      );

      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw AppException('${data['error']}');
      }
      // La contraseña cambió pero no se pudo marcar como temporal.
      if (data is Map && data['warning'] != null) {
        return '${data['warning']}';
      }
      return null;
    } on AppException {
      rethrow;
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Profile> updateName(String profileId, String fullName) async {
    try {
      final row = await _db
          .from(Tables.profiles)
          .update({'full_name': fullName.trim()})
          .eq('id', profileId)
          .select()
          .single();
      return Profile.fromMap(row);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  // ------------------------------------------------- Puestos de un trabajador

  /// Últimos cambios en las tablas de configuración.
  ///
  /// La página es pequeña a propósito: esto se mira para responder «quién
  /// tocó esto», no para leerlo entero. Traer mil filas para enseñar veinte
  /// sería pagar el coste sin usarlo.
  Future<List<AuditEntry>> fetchAuditLog({
    String? tableName,
    String? recordId,
    int limit = 60,
    int offset = 0,
  }) async {
    try {
      var query = _db.from(Views.auditLog).select();
      if (tableName != null) query = query.eq('table_name', tableName);
      if (recordId != null) query = query.eq('record_id', recordId);

      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return rows.map<AuditEntry>((r) => AuditEntry.fromMap(r)).toList();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<List<Stand>> fetchAssignedStands(String profileId) async {
    try {
      final rows = await _db
          .from(Tables.userStands)
          .select('stands(*)')
          .eq('profile_id', profileId);

      return rows
          .map((r) => r['stands'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .map(Stand.fromMap)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<void> assignStand(String profileId, String standId) async {
    try {
      await _db.from(Tables.userStands).upsert(
        {'profile_id': profileId, 'stand_id': standId},
        onConflict: 'profile_id,stand_id',
      );
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<void> removeStand(String profileId, String standId) async {
    try {
      await _db
          .from(Tables.userStands)
          .delete()
          .eq('profile_id', profileId)
          .eq('stand_id', standId);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  // ------------------------------------------- Catálogo de productos por puesto

  /// Ids de los productos asignados a un puesto.
  Future<Set<String>> fetchStandProductIds(String standId) async {
    try {
      final rows = await _db
          .from(Tables.standProducts)
          .select('product_id')
          .eq('stand_id', standId)
          .eq('active', true);
      return rows.map<String>((r) => r['product_id'] as String).toSet();
    } catch (e, s) {
      throw mapError(e, s);
    }
  }
}
