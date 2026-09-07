import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/home/presentation/shell_screen.dart';
import '../services/service_providers.dart';
import '../services/supabase_service.dart';

/// Rutas de la aplicación.
///
/// Fase 1 solo declara el esqueleto y el guard de sesión: las pantallas reales
/// se implementan en las fases 2–4. `/admin` existe desde ya porque la §13
/// promete esa URL para el dashboard en computador.
class AppRoutes {
  const AppRoutes._();

  static const splash = '/';
  static const login = '/login';
  static const home = '/inicio';
  static const quickExit = '/salida';
  static const products = '/productos';
  static const movements = '/movimientos';
  static const inventories = '/inventarios';
  static const admin = '/admin';
  static const diagnostics = '/diagnostico';
  static const dashboard = '/dashboard';
}

/// Reemite cuando cambia la sesión, para que go_router reevalúe el redirect.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final signedIn = SupabaseService.isSignedIn;
      final goingToLogin = state.matchedLocation == AppRoutes.login;

      // El guard real de roles se apoya en RLS: aunque alguien fuerce una URL,
      // la base de datos no le devolverá datos que no le corresponden.
      if (!signedIn && !goingToLogin) return AppRoutes.login;
      if (signedIn && goingToLogin) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const ShellScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const ShellScreen(),
      ),
      // La pantalla de verificación de la Fase 1 sigue accesible para
      // diagnosticar sesión, RLS y stock cuando algo no cuadra.
      GoRoute(
        path: AppRoutes.diagnostics,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.quickExit,
        builder: (context, state) => const ShellScreen(),
      ),
      GoRoute(
        path: AppRoutes.products,
        builder: (context, state) =>
            const _PendingScreen(title: 'Productos', phase: 'Fase 2'),
      ),
      GoRoute(
        path: AppRoutes.movements,
        builder: (context, state) =>
            const _PendingScreen(title: 'Movimientos', phase: 'Fase 2'),
      ),
      GoRoute(
        path: AppRoutes.inventories,
        builder: (context, state) =>
            const _PendingScreen(title: 'Inventarios', phase: 'Fase 3'),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => const DashboardScreen(),
      ),
    ],
    errorBuilder: (context, state) =>
        _PendingScreen(title: 'Ruta no encontrada', phase: state.uri.path),
  );
});

/// Marcador para rutas todavía no implementadas.
class _PendingScreen extends StatelessWidget {
  const _PendingScreen({required this.title, required this.phase});

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          'Pendiente · $phase',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
