/// Validadores de formulario. Devuelven null si el valor es válido.
class Validators {
  const Validators._();

  static String? required(String? value, [String field = 'Este campo']) =>
      (value == null || value.trim().isEmpty) ? '$field es obligatorio' : null;

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'El correo es obligatorio';
    final ok = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value.trim());
    return ok ? null : 'Correo no válido';
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'La contraseña es obligatoria';
    // Supabase Auth exige 6 caracteres por defecto.
    return value.length < 6 ? 'Mínimo 6 caracteres' : null;
  }

  /// Cantidad de un movimiento: entero positivo (el signo lo da el tipo).
  static String? quantity(String? value) {
    if (value == null || value.trim().isEmpty) return 'Indica la cantidad';
    final n = int.tryParse(value.trim());
    if (n == null) return 'Debe ser un número entero';
    if (n <= 0) return 'Debe ser mayor que 0';
    return null;
  }

  /// Cantidad contada en un inventario físico: acepta 0 (no hay nada).
  static String? countedQuantity(String? value) {
    if (value == null || value.trim().isEmpty) return 'Indica lo que contaste';
    final n = int.tryParse(value.trim());
    if (n == null) return 'Debe ser un número entero';
    if (n < 0) return 'No puede ser negativa';
    return null;
  }

  /// Longitud mínima de una contraseña nueva.
  ///
  /// Seis es el mínimo de Supabase, y es poco: se rompe por fuerza bruta en
  /// minutos, y con esa clave se registran movimientos de stock. Se decidió
  /// así a propósito, porque exigir doce hacía que nadie cambiara nunca la
  /// suya — una contraseña fuerte que no se usa protege menos que una débil
  /// que sí.
  ///
  /// Lo que sostiene la seguridad no es esta cifra, sino las dos
  /// comprobaciones que siguen: la lista de palabras filtradas de abajo y,
  /// sobre todo, el contraste contra Have I Been Pwned al guardar. El
  /// generador, que está a un toque, sigue produciendo dieciocho.
  static const minPasswordLength = 6;

  /// Contraseña nueva, con algo más de exigencia que la del login.
  ///
  /// El aviso de «revisa tus contraseñas» aparece cuando la credencial figura
  /// en alguna filtración conocida. La longitud ayuda poco a evitarlo: lo que
  /// lo evita es que la contraseña no esté en esas listas, y eso se comprueba
  /// de verdad al guardar.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'La contraseña es obligatoria';
    if (v.length < minPasswordLength) {
      return 'Mínimo $minPasswordLength caracteres';
    }

    final variety = [
      RegExp(r'[a-z]'),
      RegExp(r'[A-Z]'),
      RegExp(r'\d'),
      RegExp(r'[^\w\s]'),
    ].where((r) => r.hasMatch(v)).length;

    // Dos clases y no tres: con seis caracteres, exigir tres obliga a meter
    // un símbolo en algo que se va a teclear a diario en un móvil.
    if (variety < 2) {
      return 'Mezcla al menos letras y números';
    }

    // Longitud y variedad no bastan: `Admin123admin` cumple las dos y está en
    // todas las listas de filtraciones, que es exactamente lo que hace saltar
    // el aviso del navegador. Estas palabras aparecen en las contraseñas más
    // filtradas del mundo y no dejan de estarlo por añadirles dígitos.
    const banned = [
      'admin', 'password', 'contrasena', 'contraseña', 'clave',
      'invictor', 'usuario', 'qwerty', 'asdf', 'letmein', 'welcome',
      'iloveyou', 'abc123', 'monkey', 'dragon', 'master',
    ];
    final lower = v.toLowerCase();
    for (final word in banned) {
      if (lower.contains(word)) {
        return 'No uses «$word»: está en las listas de contraseñas filtradas';
      }
    }

    // Escaleras de teclado y de dígitos, con o sin más texto alrededor.
    const sequences = ['0123', '1234', '2345', '3456', '4567', '5678',
        '6789', '9876', '4321', 'abcd'];
    for (final seq in sequences) {
      if (lower.contains(seq)) {
        return 'Evita secuencias como «$seq»';
      }
    }

    // Una sola palabra repetida o un carácter repetido no añaden nada.
    if (RegExp(r'(.)\1{3,}').hasMatch(v)) {
      return 'Demasiados caracteres repetidos seguidos';
    }

    return null;
  }

  /// Cantidad que se puede dejar en blanco: vacío equivale a 0.
  ///
  /// Se usa en el formulario de producto, donde tanto las existencias
  /// iniciales como el umbral de alerta son opcionales. Sin validador, un
  /// "10 unidades" escrito con letra se guardaba como 0 en silencio.
  static String? optionalQuantity(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null) return 'Debe ser un número entero';
    if (n < 0) return 'No puede ser negativa';
    return null;
  }

  static String? price(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Precio no válido';
    if (n < 0) return 'No puede ser negativo';
    return null;
  }
}
