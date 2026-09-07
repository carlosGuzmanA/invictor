import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import 'supabase_service.dart';

/// Subida y lectura de fotografías de inventario (§5).
///
/// La base de datos guarda solo la ruta del archivo, nunca el binario.
/// El bucket es privado: las URLs se firman al momento de mostrarlas.
class StorageService {
  const StorageService();

  StorageFileApi get _bucket =>
      SupabaseService.storage.from(Env.storageBucket);

  /// Sube los bytes de una foto y devuelve la ruta a guardar en `photo_url`.
  Future<String> uploadPhoto({
    required Uint8List bytes,
    required String path,
    String contentType = 'image/jpeg',
  }) async {
    if (bytes.lengthInBytes > AppConstants.photoMaxBytes) {
      throw const AppException(
        'La fotografía supera los 8 MB. Reduce la calidad antes de subirla.',
      );
    }
    try {
      await _bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
      return path;
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  /// URL temporal para mostrar una foto del bucket privado.
  Future<String> signedUrl(String path, {int expiresInSeconds = 3600}) async {
    try {
      return await _bucket.createSignedUrl(path, expiresInSeconds);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<Uint8List> download(String path) async {
    try {
      return await _bucket.download(path);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  // ------------------------------------------------- Fotos de producto (catálogo)

  static const productBucket = 'products';

  StorageFileApi get _productBucketApi =>
      SupabaseService.storage.from(productBucket);

  /// Sube la foto de un producto y devuelve su **URL pública**.
  ///
  /// A diferencia de las fotos de inventario, el bucket de catálogo es público:
  /// se guarda la URL completa en `products.image_url` y el navegador la cachea,
  /// en lugar de pedir una firma nueva por cada producto en cada pantalla.
  Future<String> uploadProductPhoto({
    required Uint8List bytes,
    required String productId,
    String contentType = 'image/jpeg',
  }) async {
    if (bytes.lengthInBytes > 4 * 1024 * 1024) {
      throw const AppException(
        'La imagen del producto supera los 4 MB incluso comprimida.',
      );
    }
    // Ruta estable por producto: al reemplazar la foto no quedan huérfanas.
    final path = '$productId.${contentType.endsWith('png') ? 'png' : 'jpg'}';
    try {
      await _productBucketApi.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );
      // `?v=` fuerza a los navegadores a olvidar la versión anterior cacheada.
      final base = _productBucketApi.getPublicUrl(path);
      return '$base?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  Future<void> removeProductPhoto(String productId) async {
    try {
      await _productBucketApi.remove(['$productId.jpg', '$productId.png']);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }

  // ------------------------------------------------------------------ Común

  /// Solo administradores (lo aplica la policy de storage.objects).
  Future<void> remove(String path) async {
    try {
      await _bucket.remove([path]);
    } catch (e, s) {
      throw mapError(e, s);
    }
  }
}
