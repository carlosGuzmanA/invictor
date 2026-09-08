/// Identidad de esta compilación.
///
/// Los valores se inyectan al compilar con `--dart-define` desde
/// `scripts/vercel_build.sh`. Sirven para responder una pregunta concreta que
/// una PWA vuelve difícil: **¿el teléfono está viendo el código nuevo?**
///
/// El service worker sirve la versión cacheada y descarga la nueva en segundo
/// plano, así que tras desplegar puedes seguir viendo la anterior sin ningún
/// aviso. Con esto se compara lo que el dispositivo ejecuta contra lo que hay
/// publicado.
class BuildInfo {
  const BuildInfo._();

  /// Versión legible del `pubspec.yaml`.
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  /// Hash corto del commit compilado. `local` cuando se compila sin git.
  static const commit = String.fromEnvironment(
    'BUILD_COMMIT',
    defaultValue: 'local',
  );

  /// Marca de tiempo de la compilación, en ISO 8601 UTC.
  static const builtAt = String.fromEnvironment('BUILD_TIME');

  /// Identificador único de esta compilación: lo que se compara contra el
  /// servidor para saber si hay algo más reciente.
  static String get id => '$version+$commit';

  /// Etiqueta breve para mostrar en la interfaz.
  static String get label => 'v$version · $commit';

  static DateTime? get builtAtDate =>
      builtAt.isEmpty ? null : DateTime.tryParse(builtAt);

  /// Compilado sin información de git: desarrollo local.
  static bool get isLocal => commit == 'local';
}
