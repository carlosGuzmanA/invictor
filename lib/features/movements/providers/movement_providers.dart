import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/enums.dart';
import '../../../data/models/inventory_movement.dart';
import '../../../services/service_providers.dart';
import '../../stands/providers/stand_providers.dart';

/// Filtros del historial. Inmutable para que Riverpod detecte los cambios.
class MovementFilter {
  /// Por defecto, solo hoy: el historial se abre para ver qué acaba de pasar
  /// en el puesto, y una semana de movimientos entierra eso.
  const MovementFilter({this.type, this.days = 1});

  /// null = todos los tipos.
  final MovementType? type;

  /// Ventana en días. 0 = sin límite.
  final int days;

  MovementFilter copyWith({MovementType? type, int? days, bool clearType = false}) =>
      MovementFilter(
        type: clearType ? null : (type ?? this.type),
        days: days ?? this.days,
      );

  @override
  bool operator ==(Object other) =>
      other is MovementFilter && other.type == type && other.days == days;

  @override
  int get hashCode => Object.hash(type, days);
}

class MovementFilterNotifier extends Notifier<MovementFilter> {
  @override
  MovementFilter build() => const MovementFilter();

  void setType(MovementType? type) =>
      state = state.copyWith(type: type, clearType: type == null);

  void setDays(int days) => state = state.copyWith(days: days);
}

final movementFilterProvider =
    NotifierProvider<MovementFilterNotifier, MovementFilter>(
        MovementFilterNotifier.new);

/// Historial del puesto activo, según los filtros vigentes.
final movementHistoryProvider =
    FutureProvider.autoDispose<List<InventoryMovement>>((ref) async {
  final stand = await ref.watch(activeStandProvider.future);
  if (stand == null) return const [];

  final filter = ref.watch(movementFilterProvider);
  return ref.watch(movementServiceProvider).fetchMovements(
        standId: stand.id,
        type: filter.type,
        from: filter.days == 0
            ? null
            : DateTime.now().subtract(Duration(days: filter.days)),
        limit: 100,
      );
});

/// Productos con una salida rápida en vuelo.
///
/// Vive en un provider y no en el `State` de la pantalla por dos razones: el
/// estado sobrevive a que el widget se reconstruya (cambiar de pestaña y
/// volver), y un campo nuevo en un `State` queda sin inicializar tras un hot
/// reload, lo que revienta con "Cannot read properties of undefined".
class PendingExits extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool contains(String productId) => state.contains(productId);

  void start(String productId) => state = {...state, productId};

  void finish(String productId) =>
      state = {...state}..remove(productId);
}

final pendingExitsProvider =
    NotifierProvider<PendingExits, Set<String>>(PendingExits.new);
