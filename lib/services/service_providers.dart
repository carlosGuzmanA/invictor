import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/profile.dart';
import '../data/models/stand.dart';
import 'admin_service.dart';
import 'auth_service.dart';
import 'catalog_service.dart';
import 'dashboard_service.dart';
import 'inventory_service.dart';
import 'movement_service.dart';
import 'photo_service.dart';
import 'presence_service.dart';
import 'realtime_service.dart';
import 'storage_service.dart';

/// Inyección de dependencias con Riverpod.
/// Las pantallas consumen estos providers, nunca instancian servicios a mano.

final authServiceProvider = Provider((ref) => const AuthService());
final adminServiceProvider = Provider((ref) => const AdminService());
final catalogServiceProvider = Provider((ref) => const CatalogService());
final dashboardServiceProvider = Provider((ref) => const DashboardService());
final movementServiceProvider = Provider((ref) => const MovementService());
final storageServiceProvider = Provider((ref) => const StorageService());
final inventoryServiceProvider = Provider((ref) => const InventoryService());
final photoServiceProvider = Provider((ref) => const PhotoService());
final presenceServiceProvider = Provider((ref) => const PresenceService());
final realtimeServiceProvider = Provider((ref) => const RealtimeService());

/// Cambios de sesión de Supabase Auth. El router escucha esto para redirigir.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authServiceProvider).onAuthStateChange,
);

/// Perfil del usuario autenticado (rol incluido). Null si no hay sesión.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  // Se recalcula en cada cambio de sesión.
  await ref.watch(authStateProvider.future);
  return ref.watch(authServiceProvider).fetchCurrentProfile();
});

/// Puestos que el usuario puede operar (§19).
final assignedStandsProvider = FutureProvider<List<Stand>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return const [];
  return ref.watch(authServiceProvider).fetchAssignedStands(profile);
});

// El puesto activo vive en `features/stands/providers/stand_providers.dart`
// (activeStandProvider): se persiste entre sesiones y se revalida contra los
// puestos que RLS permite. No duplicar ese estado aquí.
