import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/breached_password.dart';
import '../../../core/utils/password_generator.dart';
import '../../../core/utils/validators.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Cambiar la contraseña con la sesión ya abierta.
///
/// El aviso de «revisa tus contraseñas» no se puede silenciar desde el sitio:
/// es el navegador comparando la credencial contra listas de filtraciones. La
/// única salida es cambiarla por una que no esté en ellas, y hasta ahora eso
/// obligaba a salir de la aplicación, pedir un correo de recuperación y
/// volver. Esa fricción es la razón de que nadie lo hiciera.
class ChangePasswordSheet extends ConsumerStatefulWidget {
  const ChangePasswordSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ChangePasswordSheet(),
    );
    return changed ?? false;
  }

  @override
  ConsumerState<ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _repeatCtrl = TextEditingController();

  bool _visible = false;
  bool _generated = false;
  bool _busy = false;
  String? _error;

  /// Aviso de que la contraseña escrita está en filtraciones conocidas.
  ///
  /// No bloquea: el usuario puede insistir. Pero entonces sabe que el aviso
  /// del navegador va a seguir saliendo, que es justo lo que se venía a
  /// resolver.
  String? _breachWarning;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _repeatCtrl.dispose();
    super.dispose();
  }

  void _generate() {
    final password = generatePassword();
    setState(() {
      _passwordCtrl.text = password;
      _repeatCtrl.text = password;
      // Generada se muestra a propósito: hay que poder copiarla o apuntarla
      // antes de guardarla, y ocultar algo que nadie ha memorizado no protege
      // de nada.
      _visible = true;
      _generated = true;
      _error = null;
      // Una generada al azar no está en ninguna lista; comprobarlo sería
      // gastar una petición para confirmar lo evidente.
      _breachWarning = null;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _passwordCtrl.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Contraseña copiada')));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    // Se comprueba al guardar y no al escribir: el foco en un móvil es poco
    // fiable y este es el único momento que importa. Una generada al azar no
    // está en ninguna lista, así que se ahorra la petición.
    //
    // Avisa y para, pero solo la primera vez: si vuelve a pulsar con el aviso
    // delante, es una decisión suya y se guarda. Bloquearlo dejaría a alguien
    // sin poder cambiar una contraseña mala por otra mala pero distinta, que
    // sigue siendo mejor que no cambiar nada.
    if (!_generated && _breachWarning == null) {
      final result = await checkBreachedPassword(_passwordCtrl.text);
      if (!mounted) return;
      if (result.isBreached) {
        setState(() {
          _busy = false;
          _breachWarning =
              'Aparece en ${result.count} filtraciones conocidas. El aviso '
              'del navegador va a seguir saliendo — usa «Generar una '
              'segura». Si aun así quieres esta, pulsa guardar otra vez.';
        });
        return;
      }
    }

    try {
      await ref
          .read(authServiceProvider)
          .changePassword(_passwordCtrl.text);

      // Le dice al navegador que el cambio terminó, que es lo que dispara la
      // oferta de guardar la nueva en el gestor. Sin esto hay que escribirla
      // otra vez en el próximo inicio de sesión.
      TextInput.finishAutofillContext();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cambiar contraseña',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.sm),
                Text(
                  'El aviso de «revisa tus contraseñas» sale cuando la actual '
                  'aparece en alguna filtración conocida. No se puede quitar '
                  'desde la aplicación: se quita cambiándola.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Space.xl),

                TextFormField(
                  controller: _passwordCtrl,
                  enabled: !_busy,
                  obscureText: !_visible,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      tooltip: _visible ? 'Ocultar' : 'Mostrar',
                      onPressed: () => setState(() => _visible = !_visible),
                    ),
                  ),
                  onChanged: (_) {
                    if (_breachWarning != null) {
                      setState(() => _breachWarning = null);
                    }
                  },
                  validator: Validators.newPassword,
                ),
                if (_breachWarning != null) ...[
                  const SizedBox(height: Space.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          _breachWarning!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.md),

                TextFormField(
                  controller: _repeatCtrl,
                  enabled: !_busy,
                  obscureText: !_visible,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Repítela',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => v == _passwordCtrl.text
                      ? null
                      : 'Las dos no coinciden',
                ),
                const SizedBox(height: Space.md),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _generate,
                        icon: const Icon(Icons.vpn_key),
                        label: const Text('Generar una segura'),
                      ),
                    ),
                    if (_generated) ...[
                      const SizedBox(width: Space.sm),
                      IconButton(
                        onPressed: _busy ? null : _copy,
                        icon: const Icon(Icons.collections),
                        tooltip: 'Copiar',
                      ),
                    ],
                  ],
                ),

                if (_generated) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    'Guárdala antes de continuar: en el gestor del navegador, '
                    'o donde la tengas a mano. Al cambiarla se cierra la '
                    'sesión en los demás dispositivos.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: Space.md),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],

                const SizedBox(height: Space.xl),
                BusyButton(
                  label: 'Guardar contraseña',
                  busy: _busy,
                  onPressed: _save,
                ),
                const SizedBox(height: Space.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
