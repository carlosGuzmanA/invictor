import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La Edge Function no la compila nadie más.
///
/// `flutter analyze` no la mira —es TypeScript sobre Deno, no Dart— y el
/// error solo aparecería al desplegarla o, peor, al pulsar el botón que la
/// llama. Un `deno check` la valida entera: tipos, imports y sintaxis.
void main() {
  test('admin-set-password compila', () async {
    final fn = File('supabase/functions/admin-set-password/index.ts');
    expect(fn.existsSync(), isTrue);

    final ProcessResult result;
    try {
      result = await Process.run('deno', ['check', fn.path]);
    } on ProcessException {
      // Sin Deno no hay nada que comprobar. Se avisa en vez de fallar: es
      // una red de seguridad, no un requisito para trabajar en el proyecto.
      markTestSkipped('deno no está instalado');
      return;
    }

    final output = '${result.stdout}${result.stderr}';
    // La primera ejecución descarga las dependencias; sin red no se puede
    // comprobar, y eso no es un fallo de la función.
    if (result.exitCode != 0 &&
        (output.contains('error sending request') ||
            output.contains('Import') && output.contains('failed'))) {
      markTestSkipped('sin red para resolver las dependencias de Deno');
      return;
    }

    expect(result.exitCode, 0, reason: output);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
