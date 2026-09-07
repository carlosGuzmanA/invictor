import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invictor/core/constants/enums.dart';
import 'package:invictor/data/models/stand_catalog_item.dart';
import 'package:invictor/features/movements/presentation/movement_sheet.dart';

/// El cálculo de "antes → después" es lo único que el trabajador ve para
/// decidir si confirma. Un signo invertido aquí descontaría al revés sin que
/// nadie lo note hasta la cuadratura.
void main() {
  StandCatalogItem item(int qty) => StandCatalogItem(
        standId: 's1',
        productId: 'p1',
        productName: 'Peluche Pokémon',
        quantity: qty,
        inCatalog: true,
      );

  Future<void> pump(
    WidgetTester tester, {
    required int stock,
    required MovementType type,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MovementSheet(
              item: item(stock),
              standId: 's1',
              type: type,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('una salida resta del stock', (tester) async {
    await pump(tester, stock: 12, type: MovementType.salida);

    expect(find.text('1'), findsOneWidget, reason: 'cantidad por defecto');
    expect(find.text('12'), findsOneWidget, reason: 'stock antes');
    expect(find.text('11'), findsOneWidget, reason: 'stock después');
  });

  testWidgets('una entrada suma al stock', (tester) async {
    await pump(tester, stock: 12, type: MovementType.entrada);
    expect(find.text('13'), findsOneWidget);
  });

  testWidgets('subir la cantidad actualiza el resultado', (tester) async {
    await pump(tester, stock: 12, type: MovementType.salida);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('3'), findsOneWidget, reason: 'cantidad');
    expect(find.text('9'), findsOneWidget, reason: '12 - 3');
  });

  testWidgets('la cantidad nunca baja de 1', (tester) async {
    await pump(tester, stock: 12, type: MovementType.salida);

    // El botón de restar debe estar deshabilitado en 1.
    final minus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.remove),
        matching: find.byType(IconButton),
      ),
    );
    expect(minus.onPressed, isNull);
  });

  testWidgets('avisa cuando el stock quedaría negativo', (tester) async {
    await pump(tester, stock: 0, type: MovementType.salida);

    expect(find.textContaining('quedará negativo'), findsOneWidget);
    expect(find.text('-1'), findsOneWidget);
  });

  testWidgets('con stock suficiente no muestra la advertencia',
      (tester) async {
    await pump(tester, stock: 5, type: MovementType.salida);
    expect(find.textContaining('quedará negativo'), findsNothing);
  });
}
