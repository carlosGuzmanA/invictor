import 'package:intl/intl.dart';

/// Formateo consistente para toda la app (locale es-CL).
class Fmt {
  const Fmt._();

  static final _currency =
      NumberFormat.currency(locale: 'es_CL', symbol: r'$', decimalDigits: 0);
  static final _integer = NumberFormat.decimalPattern('es_CL');
  static final _date = DateFormat('dd/MM/yyyy', 'es_CL');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'es_CL');
  static final _time = DateFormat('HH:mm', 'es_CL');

  static String money(num? value) => _currency.format(value ?? 0);
  static String number(num? value) => _integer.format(value ?? 0);
  static String date(DateTime? value) => value == null ? '—' : _date.format(value);
  static String dateTime(DateTime? value) =>
      value == null ? '—' : _dateTime.format(value);
  static String time(DateTime? value) => value == null ? '—' : _time.format(value);

  /// Diferencia con signo explícito: "+3", "−2", "0".
  static String signed(int? value) {
    final v = value ?? 0;
    if (v == 0) return '0';
    return v > 0 ? '+${_integer.format(v)}' : '−${_integer.format(v.abs())}';
  }

  /// "hace 5 min", "hace 2 h", "ayer".
  static String relative(DateTime? value) {
    if (value == null) return '—';
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'recién';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return 'hace ${diff.inDays} días';
    return date(value);
  }

  /// Ruta del archivo en Storage: inventory/2026/09/04/puesto-01/inv-xxx.jpg (§5.1)
  static String photoPath({
    required String standId,
    required String inventoryId,
    required String itemId,
    DateTime? at,
    String extension = 'jpg',
  }) {
    final d = at ?? DateTime.now();
    final y = d.year.toString();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final shortStand = standId.substring(0, 8);
    return '$y/$m/$day/$shortStand/$inventoryId/$itemId.$extension';
  }
}
