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

  static String? price(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = double.tryParse(value.trim().replaceAll(',', '.'));
    if (n == null) return 'Precio no válido';
    if (n < 0) return 'No puede ser negativo';
    return null;
  }
}
