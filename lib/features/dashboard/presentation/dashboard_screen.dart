import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/palette.dart';
import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/alert_sound.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/stand_summary.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/evidence_photo.dart';
import '../../../shared/widgets/product_avatar.dart';
import '../providers/dashboard_providers.dart';
import '../providers/live_providers.dart';
import 'live_settings_sheet.dart';
import 'presence_indicator.dart';
import 'sales_section.dart';
import 'stand_sales_section.dart';

/// Dashboard administrativo (§10).
///
/// Responde tres preguntas en este orden: cuánto se movió hoy, qué necesita
/// atención y qué descuadró. Los agregados los calcula la base —traer los
/// movimientos del mes para sumarlos aquí serían miles de filas por pantalla—
/// y las vistas respetan RLS: un encargado ve sus puestos, un admin todos.
///
/// Pantalla completa con su propia barra, para la ruta `/dashboard`. Dentro
/// del shell se usa [DashboardBody], que no trae barra.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: const [_DashboardActions()],
      ),
      body: const DashboardBody(),
    );
  }
}

/// Presencia, avisos y recarga. Se reutiliza en la pantalla completa y en el
/// shell, para que el administrador tenga lo mismo en los dos sitios.
class _DashboardActions extends ConsumerWidget {
  const _DashboardActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soundOn = ref.watch(soundAlertsProvider).value ?? false;

    return Row(
      children: [
        const PresenceIndicator(),
        IconButton(
          tooltip: soundOn ? 'Avisos con sonido' : 'Avisos silenciados',
          icon: Icon(soundOn
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined),
          onPressed: () => LiveSettingsSheet.show(context),
        ),
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
          onPressed: () => refreshDashboard(ref),
        ),
      ],
    );
  }
}

/// Barra de acciones del dashboard, para usarla desde el shell.
class DashboardActions extends StatelessWidget {
  const DashboardActions({super.key});

  @override
  Widget build(BuildContext context) => const _DashboardActions();
}

/// Recarga todos los bloques de indicadores.
void refreshDashboard(WidgetRef ref) {
  ref.invalidate(standSummariesProvider);
  ref.invalidate(stockAlertsProvider);
  ref.invalidate(differencesProvider);
  ref.invalidate(salesSummaryProvider);
  ref.invalidate(dailySalesProvider);
  ref.invalidate(productSalesProvider);
  ref.invalidate(monthlySalesProvider);
  ref.invalidate(salesByStandProvider);
}

/// Contenido del dashboard, sin barra propia: así sirve tanto de pantalla
/// completa como de pestaña dentro del shell del trabajador.
class DashboardBody extends ConsumerStatefulWidget {
  const DashboardBody({super.key});

  @override
  ConsumerState<DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<DashboardBody> {
  @override
  Widget build(BuildContext context) {
    // Tiempo real: cada movimiento nuevo refresca los indicadores y, si el
    // administrador lo activó, suena un aviso. La escucha va en `listen` y no
    // en `watch` para que un movimiento no reconstruya toda la pantalla.
    ref.listen(movementSignalProvider, (previous, next) {
      final signal = next.value;
      if (signal == null) return;

      refreshDashboard(ref);

      if (signal.isWorthAlerting &&
          (ref.read(soundAlertsProvider).value ?? false)) {
        playAlertSound();
      }
    });

    final profile = ref.watch(currentProfileProvider).value;

    if (profile == null || !profile.isStaff) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'Sin acceso',
        detail: 'Esta sección es para encargados y administradores.',
      );
    }

    final summaries = ref.watch(standSummariesProvider);

    return summaries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo cargar el dashboard',
        detail: e is AppException ? e.message : '$e',
        tone: EmptyTone.danger,
        onAction: () => ref.invalidate(standSummariesProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.insights_outlined,
            title: 'Sin puestos activos',
            detail: 'Crea un puesto en Administración para ver indicadores.',
          );
        }

        // Cuatro pestañas y no un scroll único: apilado, para llegar a las
        // diferencias de inventario había que pasar por delante de todo lo
        // demás, y cada pregunta que se le hace al dashboard —cuánto se
        // vendió, qué local rinde, qué hay en cada puesto, qué está mal— es
        // una consulta distinta que no se contesta con las otras al lado.
        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Ventas'),
                  Tab(text: 'Locales'),
                  Tab(text: 'Puestos'),
                  Tab(text: 'Alertas'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _RefreshableTab(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: Space.xxl),
                        children: const [SalesSection()],
                      ),
                    ),
                    const _RefreshableTab(child: StandSalesSection()),
                    _RefreshableTab(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: Space.xxl),
                        children: [
                          const _TotalsRow(),
                          const SectionHeader(label: 'Actividad por puesto'),
                          for (final s in list) _StandCard(summary: s),
                        ],
                      ),
                    ),
                    _RefreshableTab(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: Space.xxl),
                        children: const [
                          _AlertsSection(),
                          _DifferencesSection(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Cifras del día. Lo primero que se mira al abrir.
/// Envoltorio común de cada pestaña: ancho acotado y tirar para recargar.
///
/// Recarga el dashboard entero, no solo la pestaña visible: los indicadores se
/// leen juntos y refrescar únicamente lo que se ve dejaría las demás con datos
/// de hace un rato sin avisar.
class _RefreshableTab extends ConsumerWidget {
  const _RefreshableTab({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => refreshDashboard(ref),
      child: ContentWidth(maxWidth: Sizes.wideContentMax, child: child),
    );
  }
}

class _TotalsRow extends ConsumerWidget {
  const _TotalsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(dashboardTotalsProvider);
    final theme = Theme.of(context);
    if (totals == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(Space.md),
      child: GridView.count(
        crossAxisCount: MediaQuery.of(context).size.width > 640 ? 4 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: Space.sm,
        crossAxisSpacing: Space.sm,
        childAspectRatio: 1.5,
        children: [
          StatTile(
            value: Fmt.number(totals.exitsToday),
            label: 'salidas hoy',
            icon: Icons.north_east,
          ),
          StatTile(
            value: Fmt.number(totals.unitsTotal),
            label: 'unidades en stock',
            icon: Icons.inventory_2_outlined,
          ),
          StatTile(
            value: Fmt.number(totals.alerts + totals.negatives),
            label: 'alertas de stock',
            icon: Icons.warning_amber_rounded,
            tone: (totals.alerts + totals.negatives) > 0
                ? theme.semantic.warning
                : null,
          ),
          StatTile(
            value: Fmt.number(totals.openInventories),
            label: 'inventarios abiertos',
            icon: Icons.pending_actions,
            tone: totals.openInventories > 0 ? theme.semantic.info : null,
          ),
        ],
      ),
    );
  }
}

class _StandCard extends StatelessWidget {
  const _StandCard({required this.summary});

  final StandSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
      child: Card(
        child: Padding(
          padding: Insets.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    summary.isWarehouse ? Icons.warehouse : Icons.storefront,
                    size: Sizes.icon,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(summary.standName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (summary.openInventories > 0)
                    StatusPill(
                      label: 'Inventario en curso',
                      color: semantic.info,
                      icon: Icons.pending_actions,
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  _Metric(
                    value: summary.exitsToday,
                    label: 'hoy',
                  ),
                  _Metric(
                    value: summary.exitsWeek,
                    label: '7 días',
                  ),
                  _Metric(
                    value: summary.unitsTotal,
                    label: 'en stock',
                  ),
                  _Metric(
                    value: summary.productsAssigned,
                    label: 'productos',
                  ),
                ],
              ),
              if (summary.needsAttention) ...[
                const SizedBox(height: Space.md),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.xs,
                  children: [
                    if (summary.productsNegative > 0)
                      StatusPill(
                        label: '${summary.productsNegative} en negativo',
                        color: semantic.danger,
                        icon: Icons.priority_high,
                      ),
                    if (summary.productsLow > 0)
                      StatusPill(
                        label: '${summary.productsLow} con stock bajo',
                        color: semantic.warning,
                        icon: Icons.warning_amber_rounded,
                      ),
                  ],
                ),
              ],
              if (summary.lastMovementAt != null) ...[
                const SizedBox(height: Space.sm),
                Text(
                  'Último movimiento ${Fmt.relative(summary.lastMovementAt)}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Fmt.number(value),
            style: theme.textTheme.titleLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Productos que necesitan reposición o revisión.
class _AlertsSection extends ConsumerWidget {
  const _AlertsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(stockAlertsProvider);
    final theme = Theme.of(context);

    return alerts.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Column(
            children: [
              const SectionHeader(label: 'Alertas de stock'),
              Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Row(
                  children: [
                    Icon(Icons.verified,
                        size: Sizes.icon, color: theme.semantic.positive),
                    const SizedBox(width: Space.sm),
                    Text('Ningún producto bajo mínimo',
                        style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              label: 'Alertas de stock',
              trailing: Text('${list.length}',
                  style: theme.textTheme.labelSmall),
            ),
            for (final a in list.take(20)) _AlertRow(alert: a),
            if (list.length > 20)
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Text('y ${list.length - 20} más…',
                    style: theme.textTheme.labelSmall),
              ),
          ],
        );
      },
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final StockAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        alert.isNegative ? theme.semantic.danger : theme.semantic.warning;

    return ListTile(
      leading: ProductAvatar(
        imageUrl: alert.imageUrl,
        productIcon: alert.productIcon,
        categoryIcon: alert.categoryIcon,
        size: Sizes.thumb,
      ),
      title: Text(alert.productName,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${alert.standName} · mínimo ${alert.minStock}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Fmt.number(alert.quantity),
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(alert.isNegative ? 'negativo' : 'bajo',
              style: theme.textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Diferencias de inventarios cerrados, con su evidencia fotográfica.
class _DifferencesSection extends ConsumerWidget {
  const _DifferencesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final differences = ref.watch(differencesProvider);
    final theme = Theme.of(context);

    return differences.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Column(
            children: [
              const SectionHeader(label: 'Diferencias de inventario'),
              Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Row(
                  children: [
                    Icon(Icons.verified,
                        size: Sizes.icon, color: theme.semantic.positive),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        'Los inventarios cerrados cuadraron sin diferencias',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              label: 'Diferencias de inventario',
              trailing:
                  Text('${list.length}', style: theme.textTheme.labelSmall),
            ),
            for (final d in list) _DifferenceRow(difference: d),
          ],
        );
      },
    );
  }
}

class _DifferenceRow extends StatelessWidget {
  const _DifferenceRow({required this.difference});

  final InventoryDifference difference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: difference.hasPhoto
          // La evidencia se abre desde aquí: es lo que pide la §10.
          ? EvidenceThumb(
              path: difference.photoUrl!,
              size: Sizes.thumb,
              caption: '${difference.productName} · '
                  'inventario #${difference.inventoryCode}',
            )
          : Container(
              width: Sizes.thumb,
              height: Sizes.thumb,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(Icons.no_photography_outlined,
                  size: 18, color: theme.colorScheme.outline),
            ),
      title: Text(difference.productName,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '#${difference.inventoryCode} · ${difference.standName} · '
        'sistema ${difference.systemQty} → contado ${difference.countedQty}'
        '${difference.completedAt != null ? ' · ${Fmt.date(difference.completedAt)}' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: difference.note != null && difference.note!.isNotEmpty,
      trailing: DeltaText(
        difference.difference,
        style: theme.textTheme.titleMedium,
        neutralWhenZero: false,
      ),
    );
  }
}
