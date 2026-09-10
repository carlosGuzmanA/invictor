import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Resultado de comprobar una contraseña contra filtraciones conocidas.
enum BreachCheck {
  /// No aparece en ninguna filtración conocida.
  clean,

  /// Aparece. Es la razón exacta de que el navegador avise.
  breached,

  /// No se pudo comprobar —sin conexión, servicio caído—. No es un no.
  unknown,
}

/// Cuántas veces aparece la contraseña en filtraciones, o null si no se supo.
class BreachResult {
  const BreachResult(this.status, {this.count = 0});

  final BreachCheck status;
  final int count;

  bool get isBreached => status == BreachCheck.breached;
}

/// Comprueba la contraseña contra Have I Been Pwned, igual que hace Chrome.
///
/// **La contraseña no sale del dispositivo.** Se calcula su SHA-1 y se envían
/// solo los **cinco primeros caracteres** del hash; el servicio devuelve
/// todos los sufijos que empiezan así —cientos de miles— y la comparación se
/// hace aquí. Es el modelo de k-anonimato que usan Chrome, Firefox y los
/// gestores de contraseñas: el servidor no puede saber cuál se consultó.
///
/// Sirve para algo muy concreto: el aviso de «revisa tus contraseñas» sale
/// justamente cuando la credencial está en estas listas. Comprobarlo antes de
/// guardar es la diferencia entre creer que el problema está resuelto y
/// saberlo.
///
/// Ante cualquier fallo devuelve [BreachCheck.unknown] y **no bloquea**: no
/// poder comprobarlo no es motivo para impedir un cambio de contraseña.
Future<BreachResult> checkBreachedPassword(
  String password, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 6),
}) async {
  if (password.isEmpty) return const BreachResult(BreachCheck.unknown);

  final own = client == null;
  final http.Client c = client ?? http.Client();

  try {
    final digest =
        sha1.convert(utf8.encode(password)).toString().toUpperCase();
    final prefix = digest.substring(0, 5);
    final suffix = digest.substring(5);

    final response = await c
        .get(
          Uri.parse('https://api.pwnedpasswords.com/range/$prefix'),
          // Pide que la respuesta venga con relleno, para que su tamaño no
          // delate cuántos resultados tiene el prefijo consultado.
          headers: const {'Add-Padding': 'true'},
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      return const BreachResult(BreachCheck.unknown);
    }

    for (final line in const LineSplitter().convert(response.body)) {
      final parts = line.split(':');
      if (parts.length != 2) continue;
      if (parts[0].trim().toUpperCase() != suffix) continue;

      final count = int.tryParse(parts[1].trim()) ?? 0;
      // El relleno viene con recuento 0: son entradas falsas para ocultar el
      // tamaño real de la respuesta, no coincidencias.
      if (count <= 0) return const BreachResult(BreachCheck.clean);
      return BreachResult(BreachCheck.breached, count: count);
    }

    return const BreachResult(BreachCheck.clean);
  } catch (_) {
    return const BreachResult(BreachCheck.unknown);
  } finally {
    if (own) c.close();
  }
}
