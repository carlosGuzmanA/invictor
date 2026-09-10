import 'dart:math';

/// Genera una contraseña que no está en ninguna filtración.
///
/// El aviso de «revisa tus contraseñas» aparece cuando la credencial figura
/// en alguna brecha conocida. No hay forma de silenciarlo desde el sitio: es
/// el navegador comparando lo que escribes contra esas listas. La única
/// salida es una contraseña que no esté en ellas, y la manera fiable de
/// conseguirlo es no elegirla uno mismo.
///
/// Se usa [Random.secure], que toma entropía del sistema. `Random()` normal
/// es predecible a partir de su semilla y no sirve para esto.
String generatePassword({int length = 18}) {
  const lower = 'abcdefghijkmnopqrstuvwxyz';
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const digits = '23456789';
  const symbols = '!@#%^&*-_=+?';

  // Sin l/I/1 ni O/0: la contraseña se dicta por teléfono a un vendedor más
  // veces de lo que uno quisiera, y esos caracteres se confunden al leerlos.
  const all = '$lower$upper$digits$symbols';

  final random = Random.secure();
  String pick(String from) => from[random.nextInt(from.length)];

  // Uno de cada clase, garantizado: dejarlo al azar puro produce de vez en
  // cuando una contraseña sin números que el validador rechazaría.
  final chars = <String>[
    pick(lower),
    pick(upper),
    pick(digits),
    pick(symbols),
    for (var i = 4; i < length; i++) pick(all),
  ];

  // Barajar para que las cuatro obligatorias no queden siempre delante.
  for (var i = chars.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = chars[i];
    chars[i] = chars[j];
    chars[j] = tmp;
  }

  return chars.join();
}
