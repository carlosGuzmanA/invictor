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

  /// Contraseña nueva, con más exigencia que la del login.
  ///
  /// Supabase acepta seis caracteres y el navegador acepta cualquier cosa,
  /// pero el aviso de «revisa tus contraseñas» aparece cuando la credencial
  /// figura en alguna filtración conocida — y las cortas y comunes figuran
  /// todas. Doce caracteres con algo de variedad sacan la contraseña de esas
  /// listas; lo que de verdad la saca es generarla al azar.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'La contraseña es obligatoria';
    if (v.length < 12) return 'Mínimo 12 caracteres';

    final variety = [
      RegExp(r'[a-z]'),
      RegExp(r'[A-Z]'),
      RegExp(r'\d'),
      RegExp(r'[^\w\s]'),
    ].where((r) => r.hasMatch(v)).length;

    if (variety < 3) {
      return 'Combina mayúsculas, minúsculas, números y algún símbolo';
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
