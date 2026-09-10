import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La navegación cambia según el rol: un vendedor no ve el dashboard ni el
/// diagnóstico. Es cosmético en el sentido de que RLS protege los datos
/// igualmente, pero ofrecer pantallas que no dicen nada añade ruido a quien
/// trabaja de pie y con prisa.
void main() {
  final shell =
      File('lib/features/home/presentation/shell_screen.dart').readAsStringSync();

  test('el dashboard es la primera pestaña y solo para staff', () {
    // `if (isStaff)` va antes de las demás pestañas, así que al insertarse
    // queda en primera posición.
    final tabs = RegExp(r'List<_Tab> _tabsFor\(bool isStaff\) => \[([\s\S]*?)\n  \];')
        .firstMatch(shell);
    expect(tabs, isNotNull);

    final body = tabs!.group(1)!;
    final dashboardAt = body.indexOf("label: 'Dashboard'");
    final productsAt = body.indexOf("label: 'Productos'");

    expect(dashboardAt, greaterThan(-1));
    expect(dashboardAt, lessThan(productsAt),
        reason: 'para staff el dashboard debe abrirse primero');
    expect(body.substring(0, dashboardAt), contains('if (isStaff)'),
        reason: 'un vendedor no debe ver la pestaña de dashboard');
  });

  test('el vendedor conserva sus tres pestañas operativas', () {
    for (final label in ['Productos', 'Movimientos', 'Inventarios']) {
      expect(shell, contains("label: '$label'"));
    }
  });

  test('diagnóstico y administración solo para staff', () {
    for (final value in ['diagnostico', 'admin']) {
      final item = RegExp("value: '$value'").firstMatch(shell);
      expect(item, isNotNull, reason: 'falta la opción $value');

      // Las 120 caracteres previas deben contener la condición de rol.
      final start = (item!.start - 120).clamp(0, shell.length);
      expect(shell.substring(start, item.start), contains('isStaff'),
          reason: '$value debe estar oculto para un vendedor');
    }
  });

  test('el índice se acota al número de pestañas', () {
    // El perfil llega asíncrono: si el dashboard aparece o desaparece con un
    // índice guardado mayor, se saldría de rango y reventaría el build.
    expect(shell, contains('clamp(0, tabs.length - 1)'));
  });

  test('el selector de puesto no se muestra en el dashboard', () {
    expect(shell, contains('usesActiveStand'));
    expect(shell, contains('current.usesActiveStand'));
  });

  // Estas direcciones quedaron de cuando esas pantallas no existían y
  // seguían anunciando «Pendiente · Fase 2» sobre funciones que llevan meses
  // en producción. En la web las direcciones se escriben y se guardan en
  // marcadores, así que alguien acabaría viéndolo.
  group('rutas que ya no están pendientes', () {
    // Sin comentarios: el archivo explica en prosa qué decía antes, y esa
    // mención bastaba para dar el guard por incumplido.
    final router = File('lib/app/router.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('productos, movimientos e inventarios llevan al shell', () {
      for (final route in const [
        'AppRoutes.products',
        'AppRoutes.movements',
        'AppRoutes.inventories',
      ]) {
        final block = RegExp(
          'path: ${RegExp.escape(route)},[\\s\\S]{0,120}?redirect',
        );
        expect(block.hasMatch(router), isTrue,
            reason: '$route debe redirigir, no mostrar un marcador');
      }
    });

    test('ninguna ruta anuncia una fase pendiente', () {
      expect(router, isNot(contains("phase: 'Fase")));
      expect(router, isNot(contains('Pendiente · ')));
    });

    test('una dirección desconocida ofrece la salida', () {
      // Sin esto se queda en una pantalla sin nada que tocar.
      expect(router, contains('Ir al inicio'));
    });
  });
}
