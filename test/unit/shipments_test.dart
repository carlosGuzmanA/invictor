import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';
import 'package:invictor/data/models/product.dart';
import 'package:invictor/data/models/shipment.dart';
import 'package:invictor/data/models/shipment_item.dart';

/// Las encomiendas cargan con tres decisiones de dominio que no se leen en el
/// código si nadie las escribe: no hay bodega, la recepción puede ser parcial,
/// y un vendedor puede registrar un producto cuyo precio no conoce.
///
/// Estos guards existen para que cambiarlas cueste un test rojo en vez de un
/// descuadre de stock meses después.
void main() {
  final migration =
      File('supabase/migrations/0013_shipments.sql').readAsStringSync();

  /// La migración sin sus comentarios.
  ///
  /// El encabezado explica en prosa las decisiones —incluido por qué cada
  /// vista lleva `security_invoker`—, y esas menciones bastaban para dar un
  /// guard por bueno sin que el código cumpliera nada.
  final code = migration
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  group('no hay bodega: la encomienda es una entrada', () {
    test('recibir genera movimientos de entrada, no traslados', () {
      // El administrador compra en Santiago y despacha en el momento: la
      // mercadería entra al sistema aquí por primera vez. Un traslado exigiría
      // un puesto de origen que descontar, y no existe.
      expect(migration, contains("'entrada'"));
      expect(migration, isNot(contains("'traslado_entrada'")),
          reason: 'no hay puesto de origen del que trasladar');
    });

    test('el producto recibido entra al catálogo del puesto', () {
      // Sin esto tendría saldo pero no aparecería en la salida rápida:
      // `v_stand_catalog` muestra lo asignado al puesto o con saldo, y lo
      // segundo lo dejaría marcado como fuera de catálogo sin motivo.
      expect(migration, contains('insert into public.stand_products'));
    });

    test('el saldo se mueve por movimiento, nunca escribiendo stand_stock', () {
      expect(migration, contains('insert into public.inventory_movements'));
      expect(migration, isNot(contains('insert into public.stand_stock')));
      expect(migration, isNot(contains('update public.stand_stock')));
    });
  });

  group('recepción parcial', () {
    test('el faltante se calcula, no se escribe', () {
      expect(migration, contains('missing_qty'));
      expect(migration, contains('generated always as'));
      expect(migration, contains('stored'));
    });

    test('el faltante no genera movimiento', () {
      // Lo que no llegó nunca estuvo en el puesto: descontarlo sería inventar
      // una salida. El movimiento solo se inserta si llegó algo.
      expect(migration, contains('if v_qty > 0 then'));
    });

    test('recibir 0 es una respuesta válida', () {
      // Distinta de null: se esperaba el producto y no llegó nada.
      expect(migration, contains('received_qty is null or received_qty >= 0'));
    });

    test('el modelo distingue "no llegó nada" de "todavía sin recibir"', () {
      const esperado = ShipmentItem(
        id: 'i1',
        shipmentId: 's1',
        productId: 'p1',
        sentQty: 10,
        receivedQty: 0,
        missingQty: 10,
      );
      const sinRecibir = ShipmentItem(
        id: 'i2',
        shipmentId: 's1',
        productId: 'p2',
        sentQty: 10,
      );

      expect(esperado.isFullyMissing, isTrue);
      expect(esperado.isMissing, isTrue);
      expect(sinRecibir.isFullyMissing, isFalse);
      expect(sinRecibir.isMissing, isFalse);
    });
  });

  group('un vendedor registra lo que llegó', () {
    test('puede crear productos, pero solo sin precio confirmado', () {
      // Con el camino a ciegas, reservar el catálogo a staff bloquea el flujo
      // entero: llega algo que nadie creó y el vendedor espera al
      // administrador, que es la espera que esto debería eliminar.
      expect(migration, contains('create policy products_insert'));
      expect(migration, contains('price_confirmed = false'));
    });

    test('un producto pendiente sigue editable, para adjuntar la foto', () {
      // La foto se sube después de crear la fila, porque la ruta en Storage se
      // nombra con el id. Sin update, el camino a ciegas quedaría sin foto.
      expect(migration, contains('create policy products_update'));
    });

    test('borrar productos sigue siendo cosa del administrador', () {
      final deletePolicy = RegExp(
        r'create policy products_delete[\s\S]*?;',
      ).firstMatch(migration);
      expect(deletePolicy, isNotNull);
      expect(deletePolicy!.group(0), contains('is_admin()'));
    });

    test('un producto nace con precio confirmado salvo que se diga', () {
      // El default protege a los productos que ya existían: la migración los
      // deja en true, y no deben aparecer como pendientes de golpe.
      const p = Product(
        id: 'p1',
        name: 'Taza',
        price: 5990,
        minStock: 0,
        active: true,
      );
      expect(p.priceConfirmed, isTrue);
      expect(p.needsPrice, isFalse);

      expect(migration, contains('add column if not exists price_confirmed'));
      expect(migration, contains('not null default true'));
    });

    test('un producto sin precio confirmado pide que se complete', () {
      const p = Product(
        id: 'p2',
        name: 'Algo que llegó',
        price: 0,
        minStock: 0,
        active: true,
        priceConfirmed: false,
      );
      expect(p.needsPrice, isTrue);
    });
  });

  group('la recepción no se puede falsear desde el cliente', () {
    test('el estado de recibido lo fija la RPC, no un update', () {
      // Marcar una encomienda como recibida sin pasar por `receive_shipment()`
      // dejaría el puesto sin la mercadería que sí llegó.
      final map = Shipment(
        id: 's1',
        toStandId: 'st1',
        status: ShipmentStatus.enviado,
        blind: false,
        createdAt: DateTime.utc(2026, 9, 8),
      ).toInsertMap();

      expect(map.containsKey('status'), isFalse);
      expect(map.containsKey('received_at'), isFalse);
      expect(map.containsKey('received_by'), isFalse);
    });

    test('la línea no envía cantidades que no le corresponden', () {
      // `received_qty` lo fija la RPC y `missing_qty` es generada: PostgREST
      // rechaza un insert que la incluya.
      const item = ShipmentItem(
        id: 'i1',
        shipmentId: 's1',
        productId: 'p1',
        sentQty: 10,
        receivedQty: 8,
        missingQty: 2,
      );
      final map = item.toInsertMap();

      expect(map['sent_qty'], 10);
      expect(map.containsKey('received_qty'), isFalse);
      expect(map.containsKey('missing_qty'), isFalse);
    });

    test('la RPC comprueba el acceso al puesto a mano', () {
      // SECURITY DEFINER se salta RLS por definición: sin esta comprobación
      // sería un agujero para recibir encomiendas de puestos ajenos.
      //
      // Se busca dentro del cuerpo de la función, no en toda la migración:
      // `has_stand_access` aparece además en las policies de `shipments`, y
      // esa mención dejaba pasar el guard aunque la función no comprobara nada.
      final body = RegExp(
        r'create or replace function public\.receive_shipment[\s\S]*?\n\$\$;',
      ).firstMatch(code);

      expect(body, isNotNull, reason: 'no se encontró receive_shipment');
      expect(body!.group(0), contains('security definer'));
      expect(body.group(0), contains('public.has_stand_access(v_stand_id)'));
      expect(body.group(0), contains("errcode = '42501'"));
    });

    test('una encomienda ya recibida no se recibe dos veces', () {
      expect(migration, contains("v_status <> 'enviado'"));
    });

    test('recibida sin fecha de recepción es un estado imposible', () {
      expect(migration, contains('shipments_received_coherent'));
    });
  });

  // La mercadería no siempre llega por una encomienda registrada: muchas
  // veces el paquete se manda sin apuntar nada. Si el registro dependiera de
  // que exista la encomienda, lo que llegó se quedaría fuera del sistema
  // hasta que alguien contestara el teléfono.
  group('llegadas sin encomienda', () {
    final vendorMigration = File(
            'supabase/migrations/0014_vendor_registers_arrivals.sql')
        .readAsStringSync();

    test('el vendedor puede añadir productos al catálogo de su puesto', () {
      // Sin esto el producto se creaba y quedaba invisible: `v_stand_catalog`
      // solo muestra lo asignado al puesto o lo que tenga saldo. Sin error y
      // sin efecto, que es el peor resultado posible.
      expect(vendorMigration, contains('create policy stand_products_insert'));
      expect(vendorMigration, contains('public.has_stand_access(stand_id)'));
    });

    test('quitar del catálogo sigue siendo cosa de staff', () {
      final deletePolicy = RegExp(
        r'create policy stand_products_delete[\s\S]*?;',
      ).firstMatch(vendorMigration);

      expect(deletePolicy, isNotNull);
      expect(deletePolicy!.group(0), contains('is_staff()'));
    });

    test('el update existe, porque asignar es un upsert', () {
      // Si el producto ya estaba en el catálogo desactivado, la operación lo
      // reactiva; sin permiso de update fallaría por el índice único.
      expect(vendorMigration, contains('create policy stand_products_update'));
    });

    test('el botón de crear producto ya no es solo para staff', () {
      final tab = File('lib/features/home/presentation/products_tab.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');

      expect(tab, contains('canOperate && activeStand.value != null'));
      expect(tab, isNot(contains('isStaff && activeStand.value != null')),
          reason: 'un vendedor tiene que poder registrar lo que le llegó');
    });
  });

  group('interfaz de despacho y recepción', () {
    String source(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    final dispatch = source(
        'lib/features/shipments/presentation/dispatch_shipment_screen.dart');
    final receive = source(
        'lib/features/shipments/presentation/receive_shipment_screen.dart');
    final tab =
        source('lib/features/shipments/presentation/shipments_tab.dart');
    final shell =
        source('lib/features/home/presentation/shell_screen.dart');
    final form = source(
        'lib/features/products/presentation/product_form_sheet.dart');

    test('una encomienda a ciegas se despacha sin líneas', () {
      // Mandar el paquete "sin detallar" y además las líneas dejaría dos
      // versiones de la verdad: la que declaró el administrador y la que
      // encuentra el vendedor.
      expect(dispatch, contains('items: _blind'));
      expect(dispatch, contains('? const []'));
    });

    test('la recepción parte de lo despachado, no de cero', () {
      // Lo habitual es que llegue todo. Obligar a teclear cada cantidad haría
      // del caso normal el trabajo más lento.
      expect(receive, contains('_prefill'));
      expect(receive, contains('_received[item.productId] = item.sentQty!'));
    });

    test('una línea despachada no se puede borrar de la recepción', () {
      // Si no llegó, la respuesta es 0 y eso queda como faltante. Borrarla
      // haría desaparecer la constancia de lo que se reclama.
      expect(receive, contains('removable: item.sentQty == null'));
    });

    test('el vendedor puede registrar productos en una a ciegas', () {
      expect(receive, contains('_addFromCatalog'));
      expect(receive, contains('ProductFormSheet.show(context)'));
    });

    test('un precio en blanco no se confirma', () {
      // Un 0 no distingue "gratis" de "todavía no lo sé".
      expect(form, contains('hasPrice'));
      expect(form, contains('priceConfirmed: hasPrice'));
    });

    test('solo staff ve el botón de despachar', () {
      // RLS lo aplica igualmente; esto evita ofrecer lo que fallaría.
      expect(tab, contains('isStaff && hasStand'));
    });

    test('la pestaña avisa de las encomiendas sin confirmar', () {
      // Un paquete que nadie recibe es stock que el sistema no conoce.
      expect(shell, contains('ShipmentsTab()'));
      expect(shell, contains('pendingShipmentsProvider'));
      expect(shell, contains('Badge.count'));
    });

    test('la etiqueta del destino cabe en la barra', () {
      // Con cinco destinos, una etiqueta larga aprieta la barra hasta dejar
      // el icono sin sitio en un móvil estrecho — es lo que pasó con
      // «Encomiendas».
      final labels = RegExp(r"label: '([^']+)'")
          .allMatches(shell)
          .map((m) => m.group(1)!)
          .toList();

      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(label.length, lessThanOrEqualTo(12),
            reason: '«$label» no cabe junto a otros cuatro destinos');
      }
    });

    test('salir de las pantallas de encomienda está a la vista', () {
      // En la PWA instalada no hay flecha del navegador: si la pantalla no
      // ofrece salida propia, se queda encerrado.
      expect(dispatch, contains('leading: IconButton'));
      expect(receive, contains('leading: IconButton'));
    });

    test('un fallo al despachar o recibir se ve sin desplazarse', () {
      // El botón está en la barra de abajo y el mensaje al final de la lista:
      // sin el aviso emergente, pulsar parecía no hacer nada.
      expect(dispatch, contains('showSnackBar'));
      expect(receive, contains('showSnackBar'));
    });

    test('el botón se apaga en vez de fallar al pulsarlo', () {
      // Un botón llamado «añade productos» no es un botón: es una
      // instrucción disfrazada, y al pulsarla no ocurría nada visible.
      expect(dispatch, contains('_blocker'));
      expect(dispatch, contains('onPressed:\n                        blocker != null ? null :'),
          reason: 'sin nada que despachar, el botón debe estar deshabilitado');
      expect(dispatch, isNot(contains('Añade productos para despachar')));
    });

    test('lo que falta se dice antes de pulsar, no después', () {
      // El aviso vivía al final de una lista que ni siquiera estaba a la
      // vista, debajo del botón.
      expect(dispatch, contains('Elige primero el puesto de destino'));
      expect(receive, contains('Registra lo que llegó para poder confirmar'));
    });

    test('el destino viene preseleccionado con el puesto activo', () {
      // Así la pantalla nunca arranca en un estado desde el que no se puede
      // hacer nada.
      expect(dispatch, contains('activeStandProvider'));
    });

    test('no se filtran los puestos por tipo', () {
      // Filtrar las bodegas dejaba el desplegable vacío si algún puesto
      // quedaba marcado así: sin destino que elegir y sin explicación.
      expect(dispatch, isNot(contains('isWarehouse')));
    });

    test('siempre hay una salida que no depende de un icono', () {
      // La aspa del título puede no verse —fuente de iconos desactualizada,
      // sin flecha del navegador en la PWA—. Un botón de texto, no.
      // Se busca el botón, no el tooltip del icono: el tooltip no se ve.
      expect(dispatch, contains("Text('Cancelar')"));
      expect(receive, contains("Text('Volver')"));
      for (final source in [dispatch, receive]) {
        expect(source, contains('Navigator.of(context).pop()'));
      }
    });

    test('el vacío explica qué hacer si no hay encomienda registrada', () {
      // No siempre se despacha por el sistema. Sin esto, el vendedor espera
      // una encomienda que nunca va a aparecer.
      expect(tab, contains('regístralo en Productos'));
    });

    test('el faltante se ve desde la lista, sin abrir la encomienda', () {
      expect(tab, contains('shipment.hasMissing'));
    });
  });

  group('las vistas no devuelven de más', () {
    test('ambas se ejecutan con los permisos de quien consulta', () {
      // Sin `security_invoker` la vista corre como su dueño y las policies de
      // las tablas base quedan anuladas: un vendedor leería encomiendas de
      // puestos que RLS le niega. Falla en silencio — la vista funciona, solo
      // devuelve de más.
      final views = RegExp(r'create or replace view public\.(v_\w+)')
          .allMatches(code)
          .map((m) => m.group(1)!)
          .toList();

      expect(views, containsAll(['v_shipments', 'v_shipment_items']));
      expect(
        RegExp('security_invoker = true').allMatches(code).length,
        views.length,
        reason: 'cada vista necesita su propio security_invoker',
      );
    });
  });
}
