import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../services/service_providers.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Inicio de sesión. Mobile-first: campos altos, un solo botón grande (§18).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(authServiceProvider)
          .signIn(email: _emailCtrl.text, password: _passwordCtrl.text);
      // Cierra el contexto de autocompletado: el navegador entiende que el
      // acceso se completó y ofrece guardar la credencial para ESTE dominio.
      TextInput.finishAutofillContext();
      // El redirect de go_router lleva al home al detectar la sesión;
      // no hace falta navegar a mano.
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Envía el correo de recuperación al que esté escrito arriba.
  ///
  /// Pide el correo en vez de abrir otro formulario: quien llega aquí ya lo
  /// ha escrito casi siempre, y un paso más en una pantalla de rescate es un
  /// paso de más.
  Future<void> _recover() async {
    final email = _emailCtrl.text.trim();
    final invalid = Validators.email(email);
    if (invalid != null) {
      setState(() => _error = 'Escribe tu correo arriba y vuelve a pulsar.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Si $email tiene cuenta, le llega un enlace para '
                'crear una contraseña nueva. Revisa también el spam.'),
            duration: const Duration(seconds: 6),
          ),
        );
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              // En pantalla de computador el formulario no debe estirarse
              // a todo el ancho: queda ilegible.
              constraints: const BoxConstraints(maxWidth: 420),
              // AutofillGroup presenta los dos campos al navegador como un
              // único formulario de acceso. Sin él, Flutter Web los expone
              // por separado y el gestor de contraseñas no los reconoce como
              // login, lo que además alimenta las advertencias de phishing
              // de Chrome en dominios sin reputación.
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(Radii.lg),
                          ),
                          child: Icon(
                            Icons.inventory_2_outlined,
                            size: 28,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.lg),
                      Text(
                        'InVictor',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Control de inventario',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: Space.xxl),

                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Correo',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: Validators.email,
                      ),
                      const SizedBox(height: Space.md),

                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        enabled: !_busy,
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: Validators.password,
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: Space.lg),
                        Container(
                          padding: const EdgeInsets.all(Space.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(Radii.md),
                            border: Border.all(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: Sizes.icon,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: Space.sm + 2),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: Space.xl),
                      BusyButton(
                        label: 'Entrar',
                        busy: _busy,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: Space.sm),
                      // El método existía en el servicio desde el principio
                      // pero nunca se conectó: quien olvidara la contraseña
                      // se quedaba fuera sin ninguna salida desde la propia
                      // aplicación.
                      TextButton(
                        onPressed: _busy ? null : _recover,
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),

                      // Qué es esto y de quién es.
                      //
                      // Chrome marcó el dominio como «sitio engañoso». Una
                      // página que solo enseña dos campos y un botón, sin
                      // decir a qué se está entrando ni quién lo opera, es
                      // indistinguible de un formulario de phishing — y quien
                      // revise la clasificación va a ver exactamente esto.
                      // Decirlo también sirve a quien llega por error.
                      const SizedBox(height: Space.xl),
                      Divider(color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: Space.md),
                      Text(
                        'Sistema privado de control de inventario para '
                        'puestos y carritos de centros comerciales.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        'Uso exclusivo del personal autorizado. Las cuentas '
                        'las crea el administrador del negocio: no hay '
                        'registro público.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        'No se piden datos bancarios ni medios de pago.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
