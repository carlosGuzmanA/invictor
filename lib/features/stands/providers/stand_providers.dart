import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/stand.dart';
import '../../../data/models/stand_catalog_item.dart';
import '../../../services/service_providers.dart';

/// Puesto sobre el que se está operando, recordado entre sesiones.
///
/// Un trabajador atiende siempre el mismo puesto: obligarle a elegirlo cada vez
/// que abre la app es fricción pura. Se guarda el id en el dispositivo y se
/// revalida contra los puestos que RLS le permite — si le quitan la asignación,
/// la selección guardada deja de aplicarse.
class ActiveStand extends AsyncNotifier<Stand?> {
  static const _prefsKey = 'active_stand_id';

  @override
  Future<Stand?> build() async {
    final available = await ref.watch(assignedStandsProvider.future);
    if (available.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);

    // La selección guardada solo vale si sigue siendo accesible.
    final saved = available.where((s) => s.id == savedId).firstOrNull;
    if (saved != null) return saved;

    // Sin selección válida: el primer puesto operable, o el primero que haya.
    final operable = available.where((s) => !s.isWarehouse);
    return operable.firstOrNull ?? available.first;
  }

  Future<void> select(Stand stand) async {
    state = AsyncData(stand);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, stand.id);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    ref.invalidateSelf();
  }
}

final activeStandProvider =
    AsyncNotifierProvider<ActiveStand, Stand?>(ActiveStand.new);

/// Catálogo del puesto activo: productos asignados más los que tengan saldo.
/// Es la lista que alimenta la salida rápida.
///
/// Expone [applyDelta] para reflejar un movimiento **al instante**, sin esperar
/// a releer del servidor. Registrar una salida implica dos viajes de red
/// —insertar el movimiento y releer el saldo que calcula el trigger— y hacer
/// esperar al trabajador entre ambos es lo que vuelve tosco el flujo más usado
/// del sistema (§4.1). El valor real lo repone [refresh] a continuación.
class ActiveStandCatalog extends AsyncNotifier<List<StandCatalogItem>> {
  @override
  Future<List<StandCatalogItem>> build() async {
    final stand = await ref.watch(activeStandProvider.future);
    if (stand == null) return const [];
    return ref.watch(catalogServiceProvider).fetchStandCatalog(stand.id);
  }

  /// Ajuste local inmediato del stock de un producto.
  void applyDelta(String productId, int delta) {
    final current = state.value;
    if (current == null || delta == 0) return;

    state = AsyncData([
      for (final item in current)
        if (item.productId == productId)
          item.copyWith(quantity: item.quantity + delta)
        else
          item,
    ]);
  }

  /// Relee del servidor **sin vaciar la lista**: usar `invalidate` devolvería
  /// el provider a estado de carga y la lista desaparecería de la pantalla.
  Future<void> refresh() async {
    final stand = ref.read(activeStandProvider).value;
    if (stand == null) return;
    try {
      final fresh =
          await ref.read(catalogServiceProvider).fetchStandCatalog(stand.id);
      state = AsyncData(fresh);
    } catch (_) {
      // Si el refresco falla, los datos optimistas siguen en pantalla y el
      // siguiente intento los corrige. Perder la lista sería peor.
    }
  }
}

final activeStandCatalogProvider =
    AsyncNotifierProvider<ActiveStandCatalog, List<StandCatalogItem>>(
        ActiveStandCatalog.new);
