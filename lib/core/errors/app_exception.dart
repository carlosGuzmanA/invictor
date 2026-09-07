import 'package:supabase_flutter/supabase_flutter.dart';

/// Excepción de dominio con un mensaje ya listo para mostrar al usuario.
///
/// Los errores crudos de PostgREST ("new row violates row-level security
/// policy for table ...") no le sirven a un trabajador en un puesto.
class AppException implements Exception {
  const AppException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => 'AppException($code): $message';
}

/// Traduce cualquier error de Supabase a un mensaje en español.
AppException mapError(Object error, [StackTrace? stackTrace]) {
  if (error is AppException) return error;

  if (error is AuthException) {
    final message = switch (error.message.toLowerCase()) {
      final m when m.contains('invalid login') =>
        'Correo o contraseña incorrectos.',
      final m when m.contains('email not confirmed') =>
        'La cuenta aún no está confirmada.',
      final m when m.contains('rate limit') =>
        'Demasiados intentos. Espera un momento.',
      _ => 'No fue posible iniciar sesión.',
    };
    return AppException(message, code: error.statusCode, cause: error);
  }

  if (error is PostgrestException) {
    // 42501 / RLS: el usuario no tiene el rol o el puesto asignado.
    if (error.code == '42501' ||
        error.message.toLowerCase().contains('row-level security')) {
      return AppException(
        'No tienes permisos para esta acción. '
        'Revisa tu rol o los puestos que tienes asignados.',
        code: error.code,
        cause: error,
      );
    }
    // 23505: índice único (SKU repetido, inventario abierto duplicado...).
    if (error.code == '23505') {
      return AppException(
        'Ya existe un registro con esos datos.',
        code: error.code,
        cause: error,
      );
    }
    // Los RAISE EXCEPTION de nuestras funciones ya vienen en español.
    if (error.code == '23514' || error.code == 'P0001') {
      return AppException(error.message, code: error.code, cause: error);
    }
    // PGRST201: la consulta embeda una tabla con la que hay más de una relación
    // posible. Es un error del programador, no del usuario, pero sin este caso
    // se enmascara como "error al consultar" y cuesta horas encontrarlo.
    if (error.code == 'PGRST201') {
      return AppException(
        'Consulta ambigua: hay más de una relación posible entre las tablas. '
        'Hay que desambiguar el join (por ejemplo `stands!stand_id`).',
        code: error.code,
        cause: error,
      );
    }
    return AppException(
      'Error al consultar la base de datos.',
      code: error.code,
      cause: error,
    );
  }

  if (error is StorageException) {
    final message = error.message.toLowerCase();

    // Distinguir permisos de red importa: "verifica tu conexión" ante un 403
    // manda a buscar el problema donde no está.
    if (error.statusCode == '403' ||
        error.statusCode == '401' ||
        message.contains('row-level security') ||
        message.contains('unauthorized')) {
      return AppException(
        'Sin permisos para guardar la fotografía en el almacenamiento. '
        'Falta ejecutar la migración de Storage o la sesión caducó.',
        code: error.statusCode,
        cause: error,
      );
    }
    if (error.statusCode == '413' || message.contains('too large')) {
      return AppException(
        'La fotografía supera el tamaño permitido (8 MB).',
        code: error.statusCode,
        cause: error,
      );
    }
    if (message.contains('mime') || message.contains('content type')) {
      return AppException(
        'Formato de imagen no admitido. Usa JPG o PNG.',
        code: error.statusCode,
        cause: error,
      );
    }
    return AppException(
      'No fue posible subir la fotografía. Verifica tu conexión.',
      code: error.statusCode,
      cause: error,
    );
  }

  return AppException('Ocurrió un error inesperado.', cause: error);
}
