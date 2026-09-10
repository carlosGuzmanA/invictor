import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `profiles.active` existía desde el principio y no bloqueaba casi nada.
///
/// Desactivar a alguien le quitaba el rol, pero `has_stand_access()` seguía
/// devolviendo true mientras conservara sus filas en `user_stands` —así que
/// leía el stock de sus puestos y podía registrar salidas— y el catálogo
/// completo con sus precios se leía con `using (true)`.
///
/// Que la aplicación cerrara la sesión al detectarlo era una cortesía de la
/// interfaz, no una defensa: un token todavía válido consultando la API
/// directamente se saltaba la pantalla de login por completo.
void main() {
  final migration =
      File('supabase/migrations/0016_deactivate_blocks_access.sql')
          .readAsStringSync();

  /// Sin comentarios: el encabezado describe en prosa el agujero que se
  /// cierra, incluidas las cadenas que estos guards buscan.
  final code = migration
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  group('la baja se aplica en la base, no en la interfaz', () {
    test('acceder a un puesto exige estar de alta', () {
      // El agujero grande: sin esto, quitar el rol no servía de nada
      // mientras quedara la asignación al puesto.
      final fn = RegExp(
        r'create or replace function public\.has_stand_access[\s\S]*?\$\$;',
      ).firstMatch(code);

      expect(fn, isNotNull);
      expect(fn!.group(0), contains('public.is_active()'));
    });

    test('el catálogo deja de ser legible para cualquiera con sesión', () {
      // Los precios de venta y la lista de locales no son información que
      // deba conservar quien ya no trabaja aquí.
      for (final table in const ['categories', 'stands', 'products']) {
        final policy = RegExp(
          'create policy ${table}_select[\\s\\S]*?;',
        ).firstMatch(code);

        expect(policy, isNotNull, reason: 'falta la policy de $table');
        expect(policy!.group(0), contains('public.is_active()'),
            reason: '$table seguiría abierto a cuentas dadas de baja');
        expect(policy.group(0), isNot(contains('using (true)')));
      }
    });

    test('el helper comprueba la tabla, no solo el rol', () {
      final fn = RegExp(
        r'create or replace function public\.is_active[\s\S]*?\$\$;',
      ).firstMatch(code);

      expect(fn, isNotNull);
      expect(fn!.group(0), contains('and active'));
      expect(fn.group(0), contains('security definer'),
          reason: 'sin esto la propia policy de profiles lo bloquearía');
    });

    test('un perfil dado de baja puede seguir leyéndose a sí mismo', () {
      // Es lo que permite explicar «tu cuenta está desactivada» en vez de
      // mostrar pantallas vacías. Y no revela nada que esa persona no supiera.
      final policy = RegExp(
        r'create policy profiles_select[\s\S]*?;',
      ).firstMatch(code);

      expect(policy, isNotNull);
      expect(policy!.group(0), contains('id = auth.uid()'));
    });
  });

  group('la aplicación lo explica en vez de romperse', () {
    final shell = File('lib/features/home/presentation/shell_screen.dart')
        .readAsStringSync();

    test('una baja en mitad de la sesión se avisa', () {
      // RLS ya le niega los datos: sin esto vería listas vacías y errores
      // sin entender por qué.
      expect(shell, contains('!profile.active'));
      expect(shell, contains('_DeactivatedScreen'));
    });

    test('y ofrece cerrar sesión', () {
      expect(shell, contains('Tu cuenta está desactivada'));
      expect(shell, contains('signOut()'));
    });

    test('el login sigue rechazando a quien está de baja', () {
      final auth = File('lib/services/auth_service.dart').readAsStringSync();
      expect(auth, contains('if (!profile.active)'));
    });
  });

  group('qué puede hacer el administrador sobre un vendedor', () {
    final users = File(
      'lib/features/admin/presentation/users_section.dart',
    ).readAsStringSync();

    test('darlo de baja, y el aviso dice que lo aplica la base', () {
      expect(users, contains('setActive'));
      expect(users, contains('lo aplica la base'));
    });

    test('mandarle el enlace para restablecer la contraseña', () {
      // Cambiársela directamente exige `service_role`, que jamás puede
      // viajar al navegador: quien la tuviera se saltaría RLS entero.
      expect(users, contains('_sendReset'));
      expect(users, contains('sendPasswordReset'));
    });

    test('la clave de servicio no aparece en el cliente', () {
      // Sin comentarios: varios archivos explican en prosa por qué esa clave
      // NO está aquí, y esas menciones daban el guard por incumplido.
      final lib = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f
              .readAsStringSync()
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n'))
          .join('\n');

      // La clave de servicio nunca debe aparecer en el cliente: quien la
      // tuviera se saltaría RLS entero.
      final forbidden = ['service', 'role'].join('_');
      expect(lib.toLowerCase(), isNot(contains(forbidden)));
      expect(lib, isNot(contains('serviceRoleKey')));
    });

    test('sin correo se dice dónde está la única salida', () {
      expect(users, contains('panel de Supabase'));
    });
  });
}
