import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/stand.dart';
import '../../../data/models/stand_catalog_item.dart';
import '../../../services/service_providers.dart';
import '../../home/presentation/update_banner.dart';
import 'diagnostics.dart';

/// Catálogo del primer puesto accesible. Valida de una sola vez la cadena
/// completa: sesión → RLS → user_stands → stand_products → trigger de stock.
final _firstStandCatalogProvider =
    FutureProvider<(Stand, List<StandCatalogItem>)?>((ref) async {
      final stands = await ref.watch(assignedStandsProvider.future);
      final operable = stands.where((s) => !s.isWarehouse).toList();
      if (operable.isEmpty) return null;

      final stand = operable.first;
      final items = await ref
          .watch(catalogServiceProvider)
          .fetchStandCatalog(stand.id);
      return (stand, items);
    });

/// Pantalla de verificación de la Fase 1.
///
/// NO es la interfaz definitiva: existe para confirmar que la app arranca, que
/// Supabase responde y que RLS entrega exactamente los datos que corresponden.
/// Se reemplaza en la Fase 2 por el home real del trabajador.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final stands = ref.watch(assignedStandsProvider);
    final catalog = ref.watch(_firstStandCatalogProvider);
    final diagnostics = ref.watch(diagnosticsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('InVictor · Fundaciones'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(currentProfileProvider);
              ref.invalidate(assignedStandsProvider);
              ref.invalidate(diagnosticsProvider);
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Check(
            label: '1 · Configuración de Supabase',
            ok: Env.isConfigured,
            detail: Env.isConfigured
                ? Env.supabaseUrl
                : 'Faltan --dart-define SUPABASE_URL / SUPABASE_ANON_KEY',
          ),
          const SizedBox(height: 12),

          profile.when(
            loading: () => const _Check(
              label: '2 · Sesión y perfil',
              ok: null,
              detail: 'Consultando…',
            ),
            error: (e, _) =>
                _Check(label: '2 · Sesión y perfil', ok: false, detail: '$e'),
            data: (p) => _Check(
              label: '2 · Sesión y perfil',
              ok: p != null,
              detail: p == null
                  ? 'Sin sesión iniciada'
                  : '${p.displayName} · ${p.role.label}'
                        '${p.active ? '' : ' · CUENTA DESACTIVADA'}',
            ),
          ),
          const SizedBox(height: 12),

          diagnostics.when(
            loading: () => const _Check(
              label: '3 · Puestos accesibles (RLS)',
              ok: null,
              detail: 'Consultando…',
            ),
            error: (e, _) => _Check(
              label: '3 · Puestos accesibles (RLS)',
              ok: false,
              detail: '$e',
            ),
            data: (d) => _Check(
              label: '3 · Puestos accesibles (RLS)',
              ok: d.ok,
              detail: d.ok
                  ? stands.value?.map((Stand s) => s.name).join(' · ') ??
                        d.message
                  : d.message,
            ),
          ),
          const SizedBox(height: 12),

          catalog.when(
            loading: () => const _Check(
              label: '4 · Stock por puesto (trigger)',
              ok: null,
              detail: 'Consultando…',
            ),
            error: (e, _) => _Check(
              label: '4 · Stock por puesto (trigger)',
              ok: false,
              detail: '$e',
            ),
            data: (data) {
              if (data == null) {
                return _Check(
                  label: '4 · Stock por puesto (trigger)',
                  ok: false,
                  detail:
                      diagnostics.value?.message ??
                      'No hay ningún puesto operable accesible.',
                );
              }
              final (stand, items) = data;
              return _CatalogCheck(stand: stand, items: items);
            },
          ),

          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: VersionTile(dense: false),
            ),
          ),

          const SizedBox(height: 32),
          Text(
            'Pantalla de verificación de la Fase 1. Las pantallas reales '
            'llegan en la Fase 2.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuarto check: además del OK, lista el stock para poder contrastarlo con
/// lo que se cargó en el seed.
class _CatalogCheck extends StatelessWidget {
  const _CatalogCheck({required this.stand, required this.items});

  final Stand stand;
  final List<StandCatalogItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final withStock = items.where((i) => i.quantity != 0).length;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              items.isEmpty ? Icons.cancel : Icons.check_circle,
              color: items.isEmpty ? theme.colorScheme.error : Colors.green,
            ),
            title: const Text('4 · Stock por puesto (trigger)'),
            subtitle: Text(
              items.isEmpty
                  ? '${stand.name}: sin productos en catálogo ni stock.'
                  : '${stand.name} · ${items.length} productos, '
                        '$withStock con existencias',
            ),
          ),
          if (items.isNotEmpty) ...[
            const Divider(height: 1),
            for (final item in items)
              ListTile(
                dense: true,
                title: Text(item.productName),
                subtitle: Text(
                  [
                    if (item.sku != null) item.sku!,
                    if (!item.inCatalog) 'fuera de catálogo',
                    if (item.isNegative) 'NEGATIVO',
                  ].join(' · '),
                ),
                trailing: Text(
                  Fmt.number(item.quantity),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: item.isNegative
                        ? theme.colorScheme.error
                        : item.isLow
                        ? Colors.orange
                        : null,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.label, required this.ok, required this.detail});

  /// null = todavía cargando.
  final bool? ok;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (ok) {
      true => (Icons.check_circle, Colors.green),
      false => (Icons.cancel, scheme.error),
      null => (Icons.hourglass_empty, scheme.outline),
    };

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        subtitle: Text(detail),
      ),
    );
  }
}
