import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';
import 'package:invictor/data/models/sales.dart';
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

  // «Actividad por puesto» mide stock y movimientos: dice cuánto hay y cuánto
  // se movió. Cuál rinde es otra pregunta, y necesita el dinero.
  group('ventas por local', () {
    test('el ticket medio separa vender mucho barato de poco caro', () {
      const barato = StandSales(
        standId: 's1',
        standName: 'Carrito',
        units: 100,
        amount: 100000,
      );
      const caro = StandSales(
        standId: 's2',
        standName: 'Tienda',
        units: 10,
        amount: 100000,
      );

      expect(barato.averageTicket, 1000);
      expect(caro.averageTicket, 10000);
    });

    test('un puesto sin ventas no revienta el ticket medio', () {
      // Dividir por cero daría infinito y lo pintaría en pantalla.
      const sinVentas = StandSales(
        standId: 's3',
        standName: 'Parado',
        units: 0,
        amount: 0,
      );
      expect(sinVentas.averageTicket, 0);
    });

    test('las ventas de un puesto se suman entre días', () {
      // `v_sales_daily` trae una fila por día Y puesto: sin agrupar, un puesto
      // aparecería tantas veces como días tenga ventas.
      final service =
          File('lib/services/dashboard_service.dart').readAsStringSync();
      expect(service, contains('fetchSalesByStand'));
      expect(service, contains('byStand[item.standId]'));
    });

    test('se ordena por facturación, no por nombre', () {
      final service =
          File('lib/services/dashboard_service.dart').readAsStringSync();
      expect(service, contains('b.amount.compareTo(a.amount)'));
    });
  });

  // El dato estaba desde el primer día —cada movimiento guarda quién lo
  // registró— pero no se enseñaba en ninguna parte.
  group('ventas por vendedor', () {
    final migration =
        File('supabase/migrations/0015_sales_by_seller.sql').readAsStringSync();

    /// Sin comentarios: el encabezado explica en prosa por qué hace falta
    /// `security_invoker`, y esa mención daba el guard por bueno aunque la
    /// vista no lo llevara.
    final migrationCode = migration
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');

    test('la vista respeta RLS', () {
      // Sin esto, un encargado vería ventas de puestos que RLS le niega, y
      // además el nombre de gente que no puede consultar.
      expect(migrationCode, contains('security_invoker = true'));
    });

    test('un nombre en blanco no se muestra como vacío', () {
      // Un perfil recién creado tiene `full_name` en cadena vacía.
      expect(migration, contains('nullif(btrim('));

      const soloCorreo = SellerSales(
        profileId: 'u1',
        units: 3,
        amount: 3000,
        email: 'ana@ejemplo.cl',
      );
      expect(soloCorreo.displayName, 'ana@ejemplo.cl');
    });

    test('sin nombre ni correo no se inventa una identidad', () {
      // Pasa cuando quien consulta no puede leer ese perfil.
      const ajeno = SellerSales(profileId: 'u2', units: 1, amount: 100);
      expect(ajeno.displayName, 'Otro vendedor');
      expect(ajeno.isUnattributed, isFalse);
    });

    test('un movimiento sin autor se distingue de un vendedor', () {
      // Los ajustes del cierre de inventario no tienen autor humano; que
      // parecieran una persona sería inventar un vendedor fantasma.
      const sinAutor = SellerSales(profileId: null, units: 5, amount: 500);
      expect(sinAutor.isUnattributed, isTrue);
      expect(sinAutor.displayName, 'Sin registrar');
    });

    test('quien no vendió nada no revienta el ticket medio', () {
      const cero = SellerSales(profileId: 'u3', units: 0, amount: 0);
      expect(cero.averageTicket, 0);
    });

    test('las ventas de una persona se suman entre días y puestos', () {
      // La vista trae una fila por día, vendedor Y puesto: sin agrupar, cada
      // persona aparecería repetida tantas veces como combinaciones tenga.
      final service =
          File('lib/services/dashboard_service.dart').readAsStringSync();
      expect(service, contains('fetchSalesBySeller'));
      expect(service, contains('bySeller[key]'));
      expect(service, contains('{...prev.stands, ...item.stands}'),
          reason: 'un vendedor puede cubrir más de un puesto');
    });
  });

  // Lo primero que se pregunta un administrador al abrir la aplicación es
  // cuánto se vendió hoy. Si el rango arranca en una semana, ese número no
  // está en pantalla y hay que ir a buscarlo cada mañana.
  group('todo lo que filtra por fecha arranca en hoy', () {
    test('el período de ventas empieza en hoy', () {
      final providers = File(
        'lib/features/dashboard/providers/dashboard_providers.dart',
      ).readAsStringSync();
      expect(providers, contains('SalesPeriod build() => SalesPeriod.today'));
      expect(SalesPeriod.today.days, 1);
    });

    test('el historial de movimientos también', () {
      final filter = File(
        'lib/features/movements/providers/movement_providers.dart',
      ).readAsStringSync();
      expect(filter, contains('this.days = 1'));
    });

    test('los servicios de ventas no reintroducen ventanas largas', () {
      final service =
          File('lib/services/dashboard_service.dart').readAsStringSync();
      // La serie del gráfico es la excepción declarada: son 14 días porque es
      // una tendencia, no un filtro.
      final defaults = RegExp(r'int days = (\d+)')
          .allMatches(service)
          .map((m) => int.parse(m.group(1)!))
          .toList();
      expect(defaults, isNotEmpty);
      expect(defaults.where((d) => d != 1 && d != 14), isEmpty,
          reason: 'los rangos por defecto deben ser hoy');
    });

    test('«sin movimiento» NO sigue al selector', () {
      // Con el período en «Hoy», un producto que no se vendió esta mañana no
      // está parado. Atarlo al selector convertiría la lista en el catálogo
      // entero y dejaría de señalar nada.
      final providers = File(
        'lib/features/dashboard/providers/dashboard_providers.dart',
      ).readAsStringSync();
      expect(providers, contains('stagnantWindowDays'));
      expect(stagnantWindowDays, greaterThanOrEqualTo(30));

      final stagnant = RegExp(r'_stagnantSourceProvider =[\s\S]*?\}\);')
          .firstMatch(providers);
      expect(stagnant, isNotNull);
      expect(stagnant!.group(0), isNot(contains('salesPeriodProvider')));
    });
  });

  group('el dashboard se reparte en pestañas', () {
    final screen =
        File('lib/features/dashboard/presentation/dashboard_screen.dart')
            .readAsStringSync();

    test('cada pregunta tiene su pestaña', () {
      // Apilado en un scroll único, llegar a las diferencias de inventario
      // obligaba a pasar por delante de todo lo demás.
      const tabs = ['Ventas', 'Locales', 'Vendedores', 'Puestos', 'Alertas'];
      for (final tab in tabs) {
        expect(screen, contains("Tab(text: '$tab')"));
      }
      expect(screen, contains('length: ${tabs.length}'),
          reason: 'el controlador debe declarar tantas pestañas como hay');
    });

    test('recargar actualiza también las ventas por local y vendedor', () {
      // Los indicadores se leen juntos: refrescar solo lo visible dejaría el
      // resto con datos viejos sin avisar.
      final refresh = RegExp(r'void refreshDashboard[\s\S]*?\n\}')
          .firstMatch(screen);
      expect(refresh, isNotNull);
      expect(refresh!.group(0), contains('salesByStandProvider'));
      expect(refresh.group(0), contains('salesBySellerProvider'));
    });

    test('el período se comparte entre pestañas', () {
      // Cambiar de pestaña y encontrarse otro rango de fechas haría que los
      // números no se pudieran comparar entre sí.
      final section = File(
        'lib/features/dashboard/presentation/stand_sales_section.dart',
      ).readAsStringSync();
      expect(section, contains('salesPeriodProvider'));
    });
  });
}

