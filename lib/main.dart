import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Formatos de fecha en es-CL antes de que cualquier widget los use.
  await initializeDateFormatting('es_CL');

  // La app es mobile-first y de uso vertical en el puesto (§18).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    ProviderScope(
      child: await _buildRoot(),
    ),
  );
}

/// Si Supabase no arranca, mostrar el motivo es más útil que una pantalla
/// en blanco: en producción el error casi siempre son las variables de entorno.
Future<Widget> _buildRoot() async {
  try {
    await SupabaseService.initialize();
    return const InVictorApp();
  } catch (error) {
    return _StartupErrorApp(error: error);
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_ethernet, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'No se pudo conectar con Supabase',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  Env.isConfigured
                      ? '$error'
                      : 'Faltan SUPABASE_URL y SUPABASE_ANON_KEY.\n'
                          'Usa ./scripts/run_web.sh o pásalas con --dart-define.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
