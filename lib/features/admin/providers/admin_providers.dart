import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/category.dart';
import '../../../data/models/profile.dart';
import '../../../data/models/stand.dart';
import '../../../services/service_providers.dart';

/// Todos los puestos, incluidos los inactivos: en administración hay que poder
/// reactivar uno, y filtrando por activos sería invisible.
final allStandsProvider = FutureProvider.autoDispose<List<Stand>>(
  (ref) => ref.watch(catalogServiceProvider).fetchStands(onlyActive: false),
);

final allCategoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(catalogServiceProvider).fetchCategories(onlyActive: false),
);

final allProfilesProvider = FutureProvider.autoDispose<List<Profile>>(
  (ref) => ref.watch(adminServiceProvider).fetchProfiles(),
);

/// Puestos asignados a un trabajador concreto.
final profileStandsProvider = FutureProvider.autoDispose
    .family<List<Stand>, String>(
      (ref, profileId) =>
          ref.watch(adminServiceProvider).fetchAssignedStands(profileId),
    );

/// Productos que maneja un puesto.
final standProductIdsProvider = FutureProvider.autoDispose
    .family<Set<String>, String>(
      (ref, standId) =>
          ref.watch(adminServiceProvider).fetchStandProductIds(standId),
    );
