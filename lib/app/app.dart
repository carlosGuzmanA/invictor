import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import 'boot_screen.dart';
import 'router.dart';
import 'theme_mode_provider.dart';
import 'theme.dart';

class InVictorApp extends ConsumerStatefulWidget {
  const InVictorApp({super.key});

  @override
  ConsumerState<InVictorApp> createState() => _InVictorAppState();
}

class _InVictorAppState extends ConsumerState<InVictorApp> {
  @override
  void initState() {
    super.initState();
    // Oculta la pantalla de carga de index.html cuando Flutter ya pintó.
    WidgetsBinding.instance.addPostFrameCallback((_) => dismissBootScreen());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Mientras se lee la preferencia guardada, `system` evita el parpadeo de
    // un tema que cambia justo después de pintar.
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
