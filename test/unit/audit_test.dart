import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/data/models/audit_entry.dart';

/// El stock ya era auditable —cada movimiento guarda su autor y no se puede
/// borrar— pero el catálogo no dejaba rastro: nadie sabía quién había
/// cambiado un precio, un rol o un puesto.
void main() {
  String sinComentarios(String path) => File(path)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  final auditoria = sinComentarios('supabase/migrations/0019_audit_log.sql');
  final borrado = sinComentarios('supabase/migrations/0020_remove_product.sql');

  group('el registro lo escribe la base, no la aplicación', () {
    test('son triggers', () {
      // Un registro que dependa de la aplicación se salta con una llamada
      // directa a la API, que es pública, o desde el panel de Supabase.
      expect(auditoria, contains('create trigger trg_audit_'));
      expect(auditoria, contains('after insert or update or delete'));
    });

    test('cubre las tablas de configuración', () {
      for (final tabla in const [
        'products', 'profiles', 'stands', 'categories',
        'user_stands', 'stand_products',
      ]) {
        expect(auditoria, contains("'$tabla'"), reason: 'falta $tabla');
      }
    });

    test('NO audita el stock ni los movimientos', () {
      // Auditar `stand_stock` generaría una fila por cada unidad vendida,
      // duplicando el volumen para repetir lo que el movimiento ya dice. Y
      // `inventory_movements` ya es su propio registro inmutable.
      final tablas = RegExp(r"foreach t in array array\[([\s\S]*?)\]")
          .firstMatch(auditoria);
      expect(tablas, isNotNull);
      expect(tablas!.group(1), isNot(contains('stand_stock')));
      expect(tablas.group(1), isNot(contains('inventory_movements')));
    });

    test('nadie puede escribir ni borrar el registro', () {
      // Un registro que el auditado puede editar no es un registro.
      expect(auditoria, contains('create policy audit_log_select'));
      expect(auditoria, isNot(contains('create policy audit_log_insert')));
      expect(auditoria, isNot(contains('create policy audit_log_delete')));
    });

    test('solo staff puede leerlo', () {
      final policy = RegExp(r'create policy audit_log_select[\s\S]*?;')
          .firstMatch(auditoria);
      expect(policy!.group(0), contains('is_staff()'));
    });
  });

  group('el registro se mantiene pequeño', () {
    test('en un cambio guarda solo los campos que cambiaron', () {
      // La fila entera en cada update multiplicaría el tamaño sin añadir
      // información.
      expect(auditoria, contains('is distinct from'));
      expect(auditoria, contains('jsonb_object_agg'));
    });

    test('ignora updated_at', () {
      // Cambia en cada escritura y no dice nada que no diga ya la fecha del
      // propio registro.
      expect(auditoria, contains("nuevo.key <> 'updated_at'"));
    });

    test('un cambio sin diferencias no deja fila', () {
      expect(auditoria, contains('if v_changed is null then'));
    });

    test('la clave es un entero, no un uuid', () {
      // Se inserta mucho y se ordena por tiempo: un uuid aleatorio fragmenta
      // el índice y ocupa el doble.
      expect(auditoria, contains('bigserial'));
    });

    test('hay forma de purgarlo antes de que haga falta', () {
      expect(auditoria, contains('purge_audit_log'));
      expect(auditoria, contains('p_days < 30'),
          reason: 'purgar hasta ayer dejaría el registro sin uso');
    });
  });

  group('el autor sobrevive al borrado de su perfil', () {
    test('el nombre y el correo se copian al registrar', () {
      // Un registro que se vacía cuando alguien se va no sirve para nada.
      expect(auditoria, contains('actor_email'));
      expect(auditoria, contains('actor_name'));
    });

    test('y la referencia al perfil no arrastra la fila', () {
      expect(auditoria, contains('on delete set null'));
    });
  });

  group('eliminar un producto', () {
    test('sin movimientos se borra; con historial se desactiva', () {
      // Borrarlo dejaría ventas apuntando a un producto que no existe.
      expect(borrado, contains('inventory_movements'));
      expect(borrado, contains("return 'desactivado'"));
      expect(borrado, contains("return 'borrado'"));
    });

    test('la decisión la toma la base', () {
      // Comprobarlo en la aplicación dejaría una ventana entre la consulta y
      // el borrado.
      expect(borrado, contains('create or replace function public.remove_product'));
      expect(borrado, contains('security definer'));
    });

    test('las tallas van con su modelo', () {
      // Dejarlas huérfanas las volvería productos sueltos sin nada que los
      // agrupe.
      expect(borrado, contains('parent_id = p_product_id'));
    });

    test('solo staff', () {
      expect(borrado, contains('is_staff()'));
      expect(borrado, contains("errcode = '42501'"));
    });
  });

  group('el registro se lee sin saber SQL', () {
    AuditEntry entrada(String action, Map<String, dynamic>? changed) =>
        AuditEntry(
          id: 1,
          createdAt: DateTime.utc(2026, 9, 12),
          tableName: 'products',
          action: action,
          actor: 'Ana',
          changed: changed,
        );

    test('los nombres de tabla y acción se traducen', () {
      expect(entrada('update', null).tableLabel, 'Producto');
      expect(entrada('insert', null).actionLabel, 'creó');
      expect(entrada('delete', null).actionLabel, 'eliminó');
    });

    test('los nombres de columna también', () {
      // «price» no significa nada para quien solo usa la aplicación.
      expect(AuditEntry.fieldLabel('price'), 'precio');
      expect(AuditEntry.fieldLabel('min_stock'), 'alerta de stock');
      expect(AuditEntry.fieldLabel('role'), 'rol');
    });

    test('el resumen lista los campos cambiados', () {
      final e = entrada('update', {
        'price': {'antes': 5990, 'ahora': 7990},
        'name': {'antes': 'a', 'ahora': 'b'},
      });
      expect(e.summary, 'nombre, precio');
    });

    test('sin autor conocido, no se inventa uno', () {
      final e = AuditEntry.fromMap({
        'id': 1,
        'created_at': '2026-09-12T00:00:00Z',
        'table_name': 'products',
        'action': 'update',
        'actor': null,
      });
      expect(e.actor, 'Sistema');
    });
  });
}
