import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../data/models/stand.dart';
import '../../../services/service_providers.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../dashboard/presentation/presence_indicator.dart';
import 'update_banner.dart';
import '../../inventories/presentation/inventories_tab.dart';
import '../../movements/presentation/movement_history_screen.dart';
import '../../shipments/presentation/shipments_tab.dart';
import '../../shipments/providers/shipment_providers.dart';
import '../../stands/providers/stand_providers.dart';
import 'products_tab.dart';

/// Contenedor del área de trabajo: puesto activo arriba, pestañas abajo.
///
/// Cinco destinos para staff y cuatro para un vendedor, que es el máximo que
/// admite una `NavigationBar` sin apretarse. Añadir un sexto obligaría a
/// mover algo al menú de la derecha.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

/// Una pestaña del área de trabajo.
///
/// `usesActiveStand` distingue las pestañas que operan sobre un puesto
/// concreto de las que agregan todos: en el dashboard, el selector de puesto
/// del título no significa nada.
typedef _Tab = ({
  IconData icon,
  IconData selectedIcon,
  String label,
  Widget body,
  bool usesActiveStand,
});

class _ShellScreenState extends ConsumerState<ShellScreen> {
  int _index = 0;

  /// Para staff el dashboard va primero: un encargado o un administrador no
  /// atiende el puesto, supervisa. Un vendedor no lo ve en absoluto.
  List<_Tab> _tabsFor(bool isStaff) => [
    if (isStaff)
      (
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: 'Dashboard',
        body: const DashboardBody(),
        usesActiveStand: false,
      ),
    (
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: 'Productos',
      body: const ProductsTab(),
      usesActiveStand: true,
    ),
    // Antes de los movimientos: si llegó un paquete, revisarlo es lo primero
    // del día — y hasta que se reciba, ese stock no existe en el sistema.
    // «Envíos» y no «Encomiendas»: con cinco destinos, una etiqueta de once
    // caracteres aprieta la barra hasta dejar el icono sin sitio en un móvil
    // estrecho. La palabra completa se conserva en los títulos y los textos.
    (
      icon: Icons.local_shipping_outlined,
      selectedIcon: Icons.local_shipping,
      label: 'Envíos',
      body: const ShipmentsTab(),
      usesActiveStand: true,
    ),
    (
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      label: 'Movimientos',
      body: const MovementHistoryScreen(),
      usesActiveStand: true,
    ),
    (
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check,
      label: 'Inventarios',
      body: const InventoriesTab(),
      usesActiveStand: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final activeStand = ref.watch(activeStandProvider);
    final profile = ref.watch(currentProfileProvider).value;
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    final isStaff = profile?.isStaff ?? false;
    final tabs = _tabsFor(isStaff);
    final pendingShipments =
        ref.watch(pendingShipmentsProvider).value?.length ?? 0;
    // El perfil llega de forma asíncrona: al aparecer o desaparecer la pestaña
    // del dashboard, el índice guardado puede quedar fuera de rango.
    final index = _index.clamp(0, tabs.length - 1);
    final current = tabs[index];

    return Scaffold(
      appBar: AppBar(
        title: current.usesActiveStand
            ? activeStand.when(
                loading: () => const Text('Cargando…'),
                error: (_, _) => const Text('InVictor'),
                data: (stand) => _StandSelector(stand: stand),
              )
            : Text(current.label),
        actions: [
          // En el dashboard: presencia, avisos y recarga. En las pestañas
          // operativas no aportan y quitarían sitio al selector de puesto.
          if (!current.usesActiveStand) const DashboardActions(),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (value) {
              switch (value) {
                case 'admin':
                  context.push(AppRoutes.admin);
                case 'tema':
                  // Cicla automático -> claro -> oscuro -> automático.
                  const order = [
                    ThemeMode.system,
                    ThemeMode.light,
                    ThemeMode.dark,
                  ];
                  final next =
                      order[(order.indexOf(themeMode) + 1) % order.length];
                  ref.read(themeModeProvider.notifier).select(next);
                case 'diagnostico':
                  context.push(AppRoutes.diagnostics);
                case 'salir':
                  ref.read(authServiceProvider).signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  profile == null
                      ? 'Sin sesión'
                      : '${profile.displayName}\n${profile.role.label}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const PopupMenuDivider(),
              // Versión y estado de actualización. Sin esto, en un móvil que
              // nunca cierra la app no hay forma de saber qué código corre.
              const PopupMenuItem(enabled: false, child: VersionTile()),
              const PopupMenuDivider(),
              // Administración solo para encargado/admin; RLS lo aplica
              // igualmente, esto evita mostrar lo que no podrían usar.
              if (isStaff)
                const PopupMenuItem(
                  value: 'admin',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.tune),
                    title: Text('Administración'),
                  ),
                ),
              PopupMenuItem(
                value: 'tema',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(themeMode.icon),
                  title: const Text('Tema'),
                  trailing: Text(
                    themeMode.label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
              if (isStaff)
                const PopupMenuItem(
                  value: 'diagnostico',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.health_and_safety_outlined),
                    title: Text('Diagnóstico'),
                  ),
                ),
              const PopupMenuItem(
                value: 'salir',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ],
      ),
      // El tracker va en el árbol de TODOS los roles: es lo que hace que un
      // vendedor aparezca conectado para el administrador.
      body: Column(
        children: [
          // Aviso de versión nueva: solo aparece cuando hay una publicada
          // distinta de la que se ejecuta.
          const UpdateBanner(),
          Expanded(
            child: Stack(children: [current.body, const PresenceTracker()]),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              // El contador de encomiendas sin confirmar va en la barra: un
              // paquete que nadie recibe es stock que el sistema no conoce, y
              // sin la señal hay que entrar a la pestaña para descubrirlo.
              //
              // Solo se envuelve en `Badge` cuando hay algo que contar: un
              // badge invisible sigue reservando su espacio alrededor del
              // icono, y con cinco destinos ese margen se nota.
              icon: tab.label == 'Envíos' && pendingShipments > 0
                  ? Badge.count(
                      count: pendingShipments,
                      child: Icon(tab.icon),
                    )
                  : Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

/// Título del AppBar: muestra el puesto activo y permite cambiarlo si el
/// usuario tiene más de uno.
class _StandSelector extends ConsumerWidget {
  const _StandSelector({required this.stand});

  final Stand? stand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available =
        ref.watch(assignedStandsProvider).value ?? const <Stand>[];
    final theme = Theme.of(context);
    final current = stand;

    if (current == null) return const Text('InVictor');
    if (available.length <= 1) {
      return Text(current.name, style: theme.textTheme.titleMedium);
    }

    return PopupMenuButton<Stand>(
      tooltip: 'Cambiar de puesto',
      onSelected: (s) => ref.read(activeStandProvider.notifier).select(s),
      itemBuilder: (_) => [
        for (final s in available)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                Icon(
                  s.isWarehouse ? Icons.warehouse : Icons.storefront,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.name)),
                if (s.id == current.id) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              current.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}
