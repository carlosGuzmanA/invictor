import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../features/inventories/providers/photo_url_provider.dart';

/// Miniatura de una fotografía de evidencia. Al tocarla, se abre a pantalla
/// completa con zoom (§10: acceso a las fotografías de evidencia).
class EvidenceThumb extends ConsumerWidget {
  const EvidenceThumb({
    super.key,
    required this.path,
    this.size = 56,
    this.caption,
  });

  final String path;
  final double size;

  /// Contexto que se muestra en el visor: producto, diferencia, fecha…
  final String? caption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(photoUrlProvider(path));
    final theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: url.when(
          loading: () => Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Center(
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Tooltip(
            message: e is AppException ? e.message : 'No se pudo cargar',
            child: Container(
              color: theme.colorScheme.errorContainer,
              child: Icon(Icons.broken_image_outlined,
                  size: 20, color: theme.colorScheme.onErrorContainer),
            ),
          ),
          data: (signed) => InkWell(
            onTap: () => EvidenceViewer.open(context,
                url: signed, caption: caption),
            child: Image.network(
              signed,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: theme.colorScheme.errorContainer,
                child: const Icon(Icons.broken_image_outlined, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visor a pantalla completa con zoom y desplazamiento.
class EvidenceViewer extends StatelessWidget {
  const EvidenceViewer({super.key, required this.url, this.caption});

  final String url;
  final String? caption;

  static Future<void> open(
    BuildContext context, {
    required String url,
    String? caption,
  }) {
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EvidenceViewer(url: url, caption: caption),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(caption ?? 'Evidencia',
            style: const TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No se pudo cargar la fotografía. '
                'El enlace pudo haber caducado: vuelve a entrar a la jornada.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bloque grande para la foto general de la vitrina.
class EvidenceBanner extends ConsumerWidget {
  const EvidenceBanner({super.key, required this.path, this.caption});

  final String path;
  final String? caption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(photoUrlProvider(path));
    final theme = Theme.of(context);

    return url.when(
      loading: () => Container(
        height: 140,
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Container(
        height: 80,
        alignment: Alignment.center,
        color: theme.colorScheme.errorContainer,
        child: Text(e is AppException ? e.message : 'No se pudo cargar'),
      ),
      data: (signed) => InkWell(
        onTap: () =>
            EvidenceViewer.open(context, url: signed, caption: caption),
        child: Stack(
          children: [
            SizedBox(
              height: 140,
              width: double.infinity,
              child: Image.network(signed, fit: BoxFit.cover),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Vitrina',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
