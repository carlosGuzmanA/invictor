/// Una línea del registro de cambios (`v_audit_log`).
///
/// El stock ya era auditable —cada movimiento guarda su autor y no se puede
/// borrar— pero el catálogo no: nadie sabía quién había cambiado un precio o
/// el rol de alguien. Con varias personas usando el sistema, «esto antes
/// costaba otra cosa» es una conversación que no se puede tener sin esto.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.createdAt,
    required this.tableName,
    required this.action,
    required this.actor,
    this.recordId,
    this.recordName,
    this.fieldCount,
    this.changed,
  });

  final int id;
  final DateTime createdAt;

  /// La tabla tocada, tal como se llama en la base.
  final String tableName;

  /// `insert`, `update` o `delete`.
  final String action;

  /// Quién lo hizo. Se copió al registrar, así que sobrevive al borrado del
  /// perfil: un registro que se vacía cuando alguien se va no sirve de nada.
  final String actor;

  final String? recordId;
  final String? recordName;

  /// Cuántos campos cambiaron. Permite resumir sin traer el detalle entero.
  final int? fieldCount;

  /// En un cambio: `{"price": {"antes": 5990, "ahora": 7990}}`.
  final Map<String, dynamic>? changed;

  /// Cómo se llama esto en castellano y para alguien que no ve la base.
  String get tableLabel => switch (tableName) {
        'products' => 'Producto',
        'profiles' => 'Usuario',
        'stands' => 'Puesto',
        'categories' => 'Categoría',
        'user_stands' => 'Asignación de puesto',
        'stand_products' => 'Catálogo del puesto',
        _ => tableName,
      };

  String get actionLabel => switch (action) {
        'insert' => 'creó',
        'update' => 'cambió',
        'delete' => 'eliminó',
        _ => action,
      };

  bool get isDelete => action == 'delete';

  /// Los campos cambiados, en un texto corto para la lista.
  ///
  /// Se traducen los nombres de columna: «price» no significa nada para quien
  /// solo usa la aplicación.
  String get summary {
    if (changed == null || changed!.isEmpty) return '';
    if (action != 'update') return recordName ?? '';

    final campos = changed!.keys.map(fieldLabel).toList()..sort();
    return campos.join(', ');
  }

  /// Público porque la pantalla del registro también traduce nombres de
  /// columna al mostrar el detalle campo a campo.
  static String fieldLabel(String field) => switch (field) {
        'name' => 'nombre',
        'price' => 'precio',
        'cost' => 'costo',
        'min_stock' => 'alerta de stock',
        'active' => 'estado',
        'role' => 'rol',
        'category_id' => 'categoría',
        'image_url' => 'imagen',
        'icon' => 'icono',
        'sku' => 'código',
        'price_confirmed' => 'confirmación de precio',
        'must_change_password' => 'contraseña temporal',
        'full_name' => 'nombre',
        'variant_label' => 'talla',
        _ => field,
      };

  factory AuditEntry.fromMap(Map<String, dynamic> map) => AuditEntry(
        id: (map['id'] as num).toInt(),
        createdAt: DateTime.parse(map['created_at'] as String),
        tableName: map['table_name'] as String,
        action: map['action'] as String,
        actor: (map['actor'] as String?) ?? 'Sistema',
        recordId: map['record_id'] as String?,
        recordName: map['record_name'] as String?,
        fieldCount: (map['field_count'] as num?)?.toInt(),
        changed: map['changed'] as Map<String, dynamic>?,
      );
}
