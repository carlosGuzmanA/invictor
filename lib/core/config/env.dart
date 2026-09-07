/// Configuración de entorno.
///
/// Los valores se inyectan en tiempo de compilación con `--dart-define`
/// (ver `scripts/run_web.sh` y `.env.example`). No se usa un archivo `.env`
/// empaquetado porque en Flutter Web cualquier asset es público de todas formas.
///
/// La `anonKey` de Supabase ES pública por diseño: la seguridad real la aplica
/// Row Level Security en la base de datos, no el secreto de la llave.
/// La `service_role` key NUNCA debe aparecer en este proyecto.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Bucket de Supabase Storage para las fotografías de inventario (§5).
  static const String storageBucket =
      String.fromEnvironment('STORAGE_BUCKET', defaultValue: 'inventory');

  static const bool isProduction =
      bool.fromEnvironment('dart.vm.product', defaultValue: false);

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Falla temprano y con un mensaje claro en vez de un error opaco de red.
  static void assertConfigured() {
    if (!isConfigured) {
      throw StateError(
        'Faltan SUPABASE_URL y/o SUPABASE_ANON_KEY.\n'
        'Ejecuta la app con:\n'
        '  flutter run -d chrome \\\n'
        '    --dart-define=SUPABASE_URL=https://xxxx.supabase.co \\\n'
        '    --dart-define=SUPABASE_ANON_KEY=eyJhbGci...\n'
        'O usa ./scripts/run_web.sh tras copiar .env.example a .env',
      );
    }
  }
}
