import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/build_info.dart';

/// Comprueba si hay una versión publicada más reciente que la que se ejecuta.
///
/// Hace falta porque el service worker de una PWA sirve lo que tiene en caché
/// y descarga lo nuevo en segundo plano: tras un despliegue puedes seguir
/// usando la versión anterior durante días sin ningún aviso, sobre todo en un
/// móvil que nunca cierra la aplicación.
///
/// Compara el identificador compilado dentro del bundle contra `build.json`
/// del servidor, pedido con un parámetro que evita la caché.
class UpdateChecker {
  const UpdateChecker();

  Future<String?> fetchPublishedId() async {
    // Solo en web: en el APK la actualización se instala, no se cachea.
    if (!kIsWeb) return null;

    try {
      final response = await http
          .get(Uri.parse(
            // El sello de tiempo evita que el navegador o el service worker
            // devuelvan una copia guardada de este mismo archivo.
            'build.json?t=${DateTime.now().millisecondsSinceEpoch}',
          ))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['id'] as String?;
    } catch (_) {
      // Sin conexión o archivo ausente: no se puede saber, y molestar con un
      // error por esto sería peor que no comprobarlo.
      return null;
    }
  }
}

final updateCheckerProvider = Provider((ref) => const UpdateChecker());

/// Estado de actualización de la aplicación.
class UpdateStatus {
  const UpdateStatus({required this.running, this.published});

  /// Identificador de lo que se está ejecutando ahora.
  final String running;

  /// Identificador de lo publicado. null si no se pudo comprobar.
  final String? published;

  bool get hasUpdate => published != null && published != running;

  /// No se pudo consultar el servidor: no equivale a estar al día.
  bool get unknown => published == null;
}

/// Comprueba al arrancar y cada diez minutos.
///
/// Diez minutos es un compromiso: más frecuente son peticiones inútiles todo
/// el día, y menos hace que un despliegue tarde demasiado en anunciarse en un
/// dispositivo que permanece abierto.
final updateStatusProvider = StreamProvider<UpdateStatus>((ref) async* {
  final checker = ref.watch(updateCheckerProvider);
  final running = BuildInfo.id;

  Future<UpdateStatus> check() async => UpdateStatus(
        running: running,
        published: await checker.fetchPublishedId(),
      );

  yield await check();

  // `periodic` en lugar de un bucle con delay: se cancela solo cuando nadie
  // escucha, sin dejar un temporizador suelto.
  await for (final _ in Stream.periodic(const Duration(minutes: 10))) {
    yield await check();
  }
});
