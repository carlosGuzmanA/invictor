import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';

/// La interfaz oculta al vendedor los tipos que no puede registrar, y RLS los
/// rechaza de verdad. Si ambas listas divergen aparece uno de dos fallos:
/// la app ofrece una acción que la base rechaza (error confuso), o el vendedor
/// registra ajustes que deberían estar reservados (agujero de auditoría).
void main() {
  final migration =
      File('supabase/migrations/0003_movement_permissions.sql').readAsStringSync();

  test('los tipos operativos de Dart coinciden con la función SQL', () {
    final fn = RegExp(
      r'function public\.is_operational_movement\(([\s\S]*?)\$\$;',
    ).firstMatch(migration);
    expect(fn, isNotNull, reason: 'no se encontró is_operational_movement');

    final inSql = RegExp("'([a-z_]+)'")
        .allMatches(fn!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    final inDart =
        MovementType.operationalTypes.map((t) => t.wireValue).toSet();

    expect(inDart, inSql);
  });

  test('los ajustes NO son operativos', () {
    // Si un ajuste entrara en la lista operativa, un vendedor podría tapar
    // un descuadre y no quedaría diferencia que revisar.
    for (final t in [
      MovementType.ajustePositivo,
      MovementType.ajusteNegativo,
      MovementType.trasladoEntrada,
      MovementType.trasladoSalida,
    ]) {
      expect(
        MovementType.operationalTypes,
        isNot(contains(t)),
        reason: '${t.wireValue} no debe estar al alcance de un vendedor',
      );
    }
  });

  test('la policy de insert restringe el tipo además del puesto', () {
    final policy = RegExp(
      r'create policy movements_insert([\s\S]*?);',
    ).firstMatch(migration);
    expect(policy, isNotNull);

    final body = policy!.group(1)!;
    expect(body, contains('has_stand_access'),
        reason: 'sin esto se opera sobre puestos ajenos');
    expect(body, contains('is_operational_movement'),
        reason: 'sin esto cualquiera registra ajustes');
    expect(body, contains('is_staff'),
        reason: 'encargado y admin deben conservar todos los tipos');
  });
}
