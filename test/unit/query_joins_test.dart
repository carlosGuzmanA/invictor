import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `inventory_movements` tiene dos claves foráneas a `stands` (`stand_id` y
/// `counterpart_stand_id`). Cualquier join embebido a `stands` desde esa tabla
/// DEBE desambiguar, o PostgREST rechaza la consulta con PGRST201.
///
/// El fallo no se detecta al compilar ni con los tests de modelo: solo aparece
/// contra una base real, y se manifiesta como una pantalla que no carga.
void main() {
  test('los joins a stands desde movimientos están desambiguados', () {
    final source =
        File('lib/services/movement_service.dart').readAsStringSync();

    // Cada aparición de `stands(` dentro de un select debe llevar `stands!`.
    final ambiguous = RegExp(r"(?<!\w)stands\(").allMatches(source);

    expect(
      ambiguous,
      isEmpty,
      reason: 'usa `stands!stand_id(...)`: hay dos FK a stands y PostgREST '
          'devuelve PGRST201 con el join sin desambiguar',
    );
  });

  test('el traductor de errores explica PGRST201', () {
    final source =
        File('lib/core/errors/app_exception.dart').readAsStringSync();
    expect(source, contains('PGRST201'),
        reason: 'sin este caso el error se enmascara como genérico');
  });
}
