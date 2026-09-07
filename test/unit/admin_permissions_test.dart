import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La administración muestra u oculta acciones según el rol, pero quien manda
/// es RLS. Si la interfaz ofreciera algo que la base rechaza, el usuario vería
/// un error confuso; si ocultara algo permitido, perdería una función.
///
/// Estos guards comprueban que ambas mitades digan lo mismo.
void main() {
  String sql() => Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  String source(String path) => File(path).readAsStringSync();

  test('crear puestos es de admin en RLS y en la interfaz', () {
    expect(
      sql(),
      contains(RegExp(
        r'create policy stands_write[\s\S]*?public\.is_admin\(\)',
        caseSensitive: false,
      )),
    );
    expect(
      source('lib/features/admin/presentation/stands_section.dart'),
      contains('isAdmin'),
      reason: 'la interfaz debe reservar el alta de puestos a admin',
    );
  });

  test('editar categorías es de staff en RLS y en la interfaz', () {
    expect(
      sql(),
      contains(RegExp(
        r'create policy categories_write[\s\S]*?public\.is_staff\(\)',
        caseSensitive: false,
      )),
    );
    expect(
      source('lib/features/admin/presentation/categories_section.dart'),
      contains('isStaff'),
    );
  });

  test('cambiar roles y asignar puestos es de admin', () {
    final all = sql();
    expect(
      all,
      contains(RegExp(
        r'create policy profiles_admin_all[\s\S]*?public\.is_admin\(\)',
        caseSensitive: false,
      )),
    );
    expect(
      all,
      contains(RegExp(
        r'create policy user_stands_write[\s\S]*?public\.is_admin\(\)',
        caseSensitive: false,
      )),
    );
    expect(
      source('lib/features/admin/presentation/users_section.dart'),
      contains('isAdmin'),
    );
  });

  test('el alta de usuarios no se intenta desde el cliente', () {
    // Crear usuarios exige la service_role key, que nunca debe llegar al
    // navegador. La pantalla debe remitir a Supabase Auth, no simularlo.
    final users = source('lib/features/admin/presentation/users_section.dart');
    expect(users, isNot(contains('signUp')));
    expect(users, isNot(contains('admin.createUser')));
    expect(users, contains('Authentication'),
        reason: 'debe indicar dónde se crean los usuarios de verdad');
  });

  test('nadie puede quitarse a sí mismo el acceso', () {
    // Si un admin se desactiva o se degrada, nadie podría devolvérselo desde
    // la app y habría que arreglarlo por SQL.
    //
    // Se cuentan las DOS protecciones —rol y estado— por separado: comprobar
    // solo que exista una dejaba pasar mutar la otra.
    final users = source('lib/features/admin/presentation/users_section.dart');

    final guards = RegExp(r'_busy \|\| _isSelf').allMatches(users).length;
    expect(guards, greaterThanOrEqualTo(2),
        reason: 'deben estar bloqueados el cambio de rol Y el de estado '
            'sobre uno mismo; se encontraron $guards');

    // Y cada control concreto, para que no valgan dos guards en el mismo sitio.
    final roleBlock = RegExp(
      r'onSelectionChanged:([\s\S]{0,80})',
    ).firstMatch(users);
    expect(roleBlock?.group(1), contains('_isSelf'),
        reason: 'el cambio de rol propio debe estar deshabilitado');

    final activeBlock = RegExp(
      r"title: const Text\('Cuenta activa'\)",
    ).firstMatch(users);
    expect(activeBlock, isNotNull);
    final beforeActive = users.substring(0, activeBlock!.start);
    expect(beforeActive.split('SwitchListTile').last, contains('_isSelf'),
        reason: 'desactivarse a uno mismo debe estar deshabilitado');
  });

  test('los perfiles se desactivan, no se eliminan', () {
    final service = source('lib/services/admin_service.dart');
    expect(service, contains('setActive'));
    expect(service, isNot(contains(RegExp(r'from\(Tables\.profiles\)\s*\.delete'))),
        reason: 'borrar un perfil dejaría sin autor sus movimientos');
  });
}
