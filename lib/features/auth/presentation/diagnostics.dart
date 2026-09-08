import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/profile.dart';
import '../../../services/service_providers.dart';
import '../../../services/supabase_service.dart';

/// Por qué un usuario no ve puestos. Sin esto, "no hay puestos" y "no tienes
/// acceso a ninguno" muestran el mismo mensaje y llevan a buscar el problema
/// en el lugar equivocado.
enum StandAccessIssue {
  /// Todo correcto: hay puestos y el usuario puede operar al menos uno.
  none,

  /// La tabla `stands` está vacía: falta ejecutar 0002_seed.sql (o crearlos).
  noStandsInDatabase,

  /// Hay puestos, pero todos están marcados `active = false`.
  allStandsInactive,

  /// Hay puestos activos, pero el usuario es `vendedor` y no tiene filas en
  /// `user_stands`. Esto es RLS funcionando, no un error.
  vendorWithoutAssignments,

  /// Hay puestos activos y el usuario es staff, pero solo hay bodegas: no hay
  /// ningún puesto operable que mostrar.
  onlyWarehouses,
}

class Diagnostics {
  const Diagnostics({
    required this.issue,
    required this.standsTotal,
    required this.standsActive,
    required this.productsTotal,
    required this.accessibleStands,
    required this.profile,
  });

  final StandAccessIssue issue;
  final int standsTotal;
  final int standsActive;
  final int productsTotal;
  final int accessibleStands;
  final Profile? profile;

  bool get ok => issue == StandAccessIssue.none;

  /// Mensaje accionable: qué pasa y qué hacer.
  String get message => switch (issue) {
    StandAccessIssue.none =>
      '$accessibleStands puesto(s) accesibles · $productsTotal productos en catálogo',
    StandAccessIssue.noStandsInDatabase =>
      'La tabla `stands` está vacía. Falta ejecutar supabase/migrations/0002_seed.sql '
          '(o crear los puestos a mano).',
    StandAccessIssue.allStandsInactive =>
      'Hay $standsTotal puesto(s), pero todos están inactivos. '
          'Actualiza `stands.active = true`.',
    StandAccessIssue.vendorWithoutAssignments =>
      'Hay $standsActive puesto(s) activos, pero tu rol es '
          '"${profile?.role.label ?? '?'}" y no tienes ninguno asignado. '
          'Esto es RLS funcionando. Promuévete a admin '
          '(update public.profiles set role = \'admin\' where email = ...) '
          'o inserta una fila en user_stands.',
    StandAccessIssue.onlyWarehouses =>
      'Solo hay puestos de tipo bodega. Crea al menos un puesto o carrito.',
  };
}

/// Consulta el estado real de la base para explicar el fallo con precisión.
///
/// `stands` y `products` los puede leer cualquier usuario autenticado
/// (policy `using (true)`), así que este diagnóstico funciona incluso para un
/// vendedor sin asignaciones — que es justo cuando más falta hace.
final diagnosticsProvider = FutureProvider<Diagnostics>((ref) async {
  final db = SupabaseService.client;
  final profile = await ref.watch(currentProfileProvider.future);
  final accessible = await ref.watch(assignedStandsProvider.future);

  final standRows = await db.from(Tables.stands).select('id, active, type');
  final productRows = await db.from(Tables.products).select('id');

  final standsTotal = standRows.length;
  final standsActive = standRows
      .where((r) => (r['active'] as bool?) ?? false)
      .length;

  final issue = switch (null) {
    _ when standsTotal == 0 => StandAccessIssue.noStandsInDatabase,
    _ when standsActive == 0 => StandAccessIssue.allStandsInactive,
    _ when accessible.isEmpty && !(profile?.isStaff ?? false) =>
      StandAccessIssue.vendorWithoutAssignments,
    _ when accessible.every((s) => s.isWarehouse) && accessible.isNotEmpty =>
      StandAccessIssue.onlyWarehouses,
    _ when accessible.isEmpty => StandAccessIssue.vendorWithoutAssignments,
    _ => StandAccessIssue.none,
  };

  return Diagnostics(
    issue: issue,
    standsTotal: standsTotal,
    standsActive: standsActive,
    productsTotal: productRows.length,
    accessibleStands: accessible.length,
    profile: profile,
  );
});
