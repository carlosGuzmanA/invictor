import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';
import 'package:invictor/data/models/stand_summary.dart';
import 'package:invictor/features/dashboard/providers/dashboard_providers.dart';

void main() {
  final sql =
      File('supabase/migrations/0010_dashboard_views.sql').readAsStringSync();

  group('zona horaria', () {
    test('el día se calcula en Chile, no en UTC', () {
      // Supabase corre en UTC. Con `current_date`, a las 21:00 de un martes en
      // Chile ya sería miércoles en UTC y las salidas de la tarde aparecerían
      // contadas al día siguiente.
      expect(sql, contains('America/Santiago'));
      expect(
        sql,
        isNot(contains(RegExp(r'>=\s*current_date'))),
        reason: 'current_date usa UTC y desplaza el "hoy" varias horas',
      );
    });

    test('las salidas del día usan la función de día local', () {
      final exits = RegExp(
        r"as exits_today",
      ).firstMatch(sql);
      expect(exits, isNotNull);
      final before = sql.substring(0, exits!.start);
      expect(before.split('exits').last.isNotEmpty, isTrue);
      expect(sql, contains('public.local_day_start()'));
      expect(sql, contains('public.local_day_start(6)'));
    });
  });

  group('vistas del dashboard', () {
    test('todas respetan RLS', () {
      final views = RegExp(
        r'create or replace view public\.(v_\w+)([\s\S]*?) as\b',
      ).allMatches(sql);
      expect(views, isNotEmpty);
      for (final v in views) {
        expect(v.group(2), contains('security_invoker'),
            reason: '${v.group(1)} se saltaría RLS y mostraría puestos ajenos');
      }
    });

    test('los agregados se calculan en la base, no en Dart', () {
      final service =
          File('lib/services/dashboard_service.dart').readAsStringSync();
      // Si el servicio leyera movimientos crudos, sumaría miles de filas
      // en el cliente en cada apertura de pantalla.
      expect(service, isNot(contains('inventory_movements')));
      expect(service, contains('v_stand_summary'));
    });

    test('el resumen evita joins que multiplicarían filas', () {
      // stand_stock + stand_products + movements en un solo FROM inflaría
      // las sumas. Debe usar subconsultas escalares.
      final summary = RegExp(
        r'create or replace view public\.v_stand_summary([\s\S]*?);\s*\n',
      ).firstMatch(sql);
      expect(summary!.group(1), contains('(select count(*)'));
    });
  });

  group('totales', () {
    StandSummary stand({
      String id = 's1',
      int today = 0,
      int week = 0,
      int units = 0,
      int low = 0,
      int negative = 0,
      int open = 0,
    }) =>
        StandSummary(
          standId: id,
          standName: id,
          type: StandType.puesto,
          active: true,
          productsAssigned: 0,
          productsWithStock: 0,
          unitsTotal: units,
          productsNegative: negative,
          productsLow: low,
          exitsToday: today,
          exitsWeek: week,
          openInventories: open,
        );

    test('suma los puestos accesibles', () {
      final totals = DashboardTotals.from([
        stand(id: 's1', today: 12, week: 40, units: 100, low: 2),
        stand(id: 's2', today: 5, week: 18, units: 47, negative: 1),
      ]);
      expect(totals.exitsToday, 17);
      expect(totals.exitsWeek, 58);
      expect(totals.unitsTotal, 147);
      expect(totals.alerts, 2);
      expect(totals.negatives, 1);
      expect(totals.stands, 2);
    });

    test('sin puestos todo queda en cero, no en null', () {
      final totals = DashboardTotals.from([]);
      expect(totals.exitsToday, 0);
      expect(totals.stands, 0);
    });
  });

  group('alertas', () {
    test('la severidad la decide la base', () {
      // Así el criterio de "bajo" vive en un solo sitio.
      expect(sql, contains("then 'negativo' else 'bajo'"));
    });

    test('un saldo negativo se distingue de un stock bajo', () {
      final negative = StockAlert.fromMap({
        'stand_id': 's1',
        'stand_name': 'Puesto 1',
        'product_id': 'p1',
        'product_name': 'Oso',
        'quantity': -2,
        'min_stock': 3,
        'severity': 'negativo',
      });
      expect(negative.isNegative, isTrue);

      final low = StockAlert.fromMap({
        'stand_id': 's1',
        'stand_name': 'Puesto 1',
        'product_id': 'p2',
        'product_name': 'Llavero',
        'quantity': 2,
        'min_stock': 5,
        'severity': 'bajo',
      });
      expect(low.isNegative, isFalse);
    });
  });

  test('las diferencias solo salen de jornadas cerradas', () {
    final view = RegExp(
      r'create or replace view public\.v_inventory_differences([\s\S]*?);\s*\n',
    ).firstMatch(sql);
    expect(view!.group(1), contains("i.status = 'finalizado'"),
        reason: 'una jornada en curso todavía no tiene diferencias reales');
    expect(view.group(1), contains('ii.difference <> 0'));
  });
}

