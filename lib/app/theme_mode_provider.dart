import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia de tema, recordada en el dispositivo.
///
/// El valor inicial es `system`: la app respeta lo que el teléfono ya tenga
/// configurado, que suele ser lo que el trabajador quiere. La elección manual
/// existe porque un puesto en un pasillo iluminado y una bodega en penumbra
/// piden cosas distintas, y el ajuste automático del teléfono no siempre acierta.
class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    return _fromWire(prefs.getString(_prefsKey));
  }

  Future<void> select(ThemeMode mode) async {
    state = AsyncData(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  static ThemeMode _fromWire(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
        ThemeMode.system => 'Automático',
        ThemeMode.light => 'Claro',
        ThemeMode.dark => 'Oscuro',
      };

  IconData get icon => switch (this) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };
}
