import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Una migración puede parsear perfectamente y fallar al ejecutarse.
///
/// Pasó con `0015`: `group by s.id` mientras se seleccionaba `sm.stand_id`.
/// La sintaxis era impecable —el parser de PostgreSQL la aceptó sin una
/// queja— y Supabase la rechazó al crear la vista. El join hace iguales esas
/// dos columnas, pero agrupar por la clave de una tabla solo habilita las
/// columnas *de esa* tabla.
///
/// `scripts/check_sql_groupby.py` cubre esa clase concreta. Este test lo
/// ejecuta para que no dependa de acordarse de lanzarlo a mano.
void main() {
  test('ninguna vista agrupa por menos de lo que selecciona', () async {
    final script = File('scripts/check_sql_groupby.py');
    expect(script.existsSync(), isTrue, reason: 'falta el validador');

    final result = await Process.run('python3', [script.path]);

    // Sin `pglast` en la máquina no hay nada que comprobar. Se avisa en vez
    // de fallar: el validador es una red de seguridad, no un requisito para
    // trabajar en el proyecto.
    final output = '${result.stdout}${result.stderr}';
    if (output.contains('ModuleNotFoundError') ||
        output.contains('No module named')) {
      markTestSkipped('pglast no está instalado (pip install pglast)');
      return;
    }

    expect(result.exitCode, 0, reason: output);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
