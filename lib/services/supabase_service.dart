import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';

/// Punto único de acceso al cliente Supabase.
///
/// Nada más en la app debe llamar a `Supabase.instance` directamente: así el
/// día que cambie la inicialización (o se necesite un mock en tests) hay un
/// solo lugar que tocar.
class SupabaseService {
  const SupabaseService._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    Env.assertConfigured();

    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // La sesión se persiste sola (localStorage en web, secure storage en móvil)
        // para que el trabajador no tenga que iniciar sesión cada vez.
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.error,
      ),
    );

    _initialized = true;
    _closeChannelsOnSignOut();
  }

  /// Cierra los canales de Realtime en cuanto desaparece la sesión.
  ///
  /// `AuthService.signOut()` ya lo hace en el cierre manual, pero una sesión
  /// puede terminar sin pasar por ahí: token expirado, contraseña cambiada, o
  /// cierre desde otro dispositivo. Sin esto, el canal de presencia quedaría
  /// abierto con un token muerto y el usuario seguiría apareciendo conectado.
  static void _closeChannelsOnSignOut() {
    auth.onAuthStateChange.listen((state) {
      if (state.session == null) {
        // Sin await: es un listener y un fallo aquí no debe romper el flujo
        // de autenticación.
        client.removeAllChannels().catchError(
              (_) => <String>[],
            );
      }
    });
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
  static SupabaseStorageClient get storage => client.storage;

  static Session? get session => auth.currentSession;
  static User? get currentUser => auth.currentUser;
  static String? get currentUserId => currentUser?.id;
  static bool get isSignedIn => session != null;
}
