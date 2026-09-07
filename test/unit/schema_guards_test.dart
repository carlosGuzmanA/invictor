import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Invariantes del esquema que son fáciles de romper sin darse cuenta y cuyo
/// fallo es silencioso: no producen error, solo abren un agujero de seguridad
/// o desincronizan el stock.
void main() {
  final schema = File('supabase/migrations/0001_schema.sql').readAsStringSync();

  test('toda vista declara security_invoker', () {
    // Sin esta opción una vista corre con los permisos de su dueño y anula las
    // policies RLS de las tablas base: un vendedor leería stock ajeno.
    final views = RegExp(
      r'create or replace view public\.(\w+)([\s\S]*?) as\b',
      caseSensitive: false,
    ).allMatches(schema);

    expect(views, isNotEmpty, reason: 'no se encontró ninguna vista');

    for (final v in views) {
      expect(
        v.group(2),
        contains('security_invoker'),
        reason: 'la vista ${v.group(1)} se saltaría RLS',
      );
    }
  });

  test('el trigger de alta no lee el rol desde metadata del cliente', () {
    final fn = RegExp(
      r'function public\.handle_new_auth_user\(\)([\s\S]*?)\$\$;',
    ).firstMatch(schema);
    expect(fn, isNotNull);

    // raw_user_meta_data lo controla quien se registra: leer el rol de ahí
    // permitiría auto-asignarse 'admin' en el signup.
    expect(
      fn!.group(1),
      isNot(contains("raw_user_meta_data ->> 'role'")),
      reason: 'escalada de privilegios en el alta de usuarios',
    );
  });

  test('las funciones SECURITY DEFINER de negocio validan permisos', () {
    for (final name in ['open_inventory', 'finalize_inventory']) {
      final fn = RegExp(
        'function public\\.$name\\(([\\s\\S]*?)\\\$\\\$;',
      ).firstMatch(schema);
      expect(fn, isNotNull, reason: 'no se encontró $name');
      expect(
        fn!.group(1),
        contains('has_stand_access'),
        reason: '$name se salta RLS por ser SECURITY DEFINER y no lo compensa',
      );
    }

    final rebuild = RegExp(
      r'function public\.rebuild_stand_stock\(\)([\s\S]*?)\$\$;',
    ).firstMatch(schema);
    expect(rebuild!.group(1), contains('is_admin'));
  });

  test('stand_stock no tiene policies de escritura', () {
    // El saldo lo mantiene el trigger. Si el cliente pudiera escribirlo,
    // dejaría de ser reconstruible desde inventory_movements.
    for (final op in ['insert', 'update', 'delete']) {
      expect(
        schema.contains(RegExp(
          'on public\\.stand_stock\\s+for $op',
          caseSensitive: false,
        )),
        isFalse,
        reason: 'existe una policy de $op sobre stand_stock',
      );
    }
  });

  test('RLS habilitado en todas las tablas de public', () {
    final tables = RegExp(r'create table if not exists public\.(\w+)')
        .allMatches(schema)
        .map((m) => m.group(1)!)
        .toSet();

    expect(tables.length, 10, reason: 'cambió el número de tablas');

    for (final t in tables) {
      expect(
        schema,
        contains('alter table public.$t'),
        reason: 'la tabla $t no aparece en un alter table',
      );
      expect(
        schema.contains(RegExp(
          'alter table public\\.$t\\s+enable row level security',
          caseSensitive: false,
        )),
        isTrue,
        reason: 'RLS no habilitado en $t',
      );
    }
  });
}
