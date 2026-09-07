import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/service_providers.dart';

/// URL firmada para mostrar una foto del bucket privado.
///
/// El bucket no es público, así que cada imagen necesita una URL temporal.
/// Se cachea por ruta: sin esto se pediría una firma nueva en cada rebuild,
/// que es una llamada de red por cada scroll.
final photoUrlProvider =
    FutureProvider.family<String, String>((ref, path) async {
  // La firma dura una hora; el provider se descarta antes de que caduque.
  ref.keepAlive();
  return ref.watch(storageServiceProvider).signedUrl(path);
});
