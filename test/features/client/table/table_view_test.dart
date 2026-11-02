import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/features/client/table/table_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RouteSettings? pushed;

  Future<void> pumpTable(WidgetTester tester) {
    pushed = null;
    return tester.pumpWidget(
      MaterialApp(
        home: const TableView(),
        onGenerateRoute: (settings) {
          pushed = settings;
          return MaterialPageRoute(builder: (_) => const Text('cardápio'));
        },
      ),
    );
  }

  testWidgets('mesa vazia mostra o erro e não navega', (tester) async {
    await pumpTable(tester);

    await tester.tap(find.text('Ver cardápio'));
    await tester.pump();

    expect(find.text('Informe o número da mesa.'), findsOneWidget);
    expect(pushed, isNull);
  });

  testWidgets('mesa válida abre o cardápio levando a mesa', (tester) async {
    await pumpTable(tester);

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Ver cardápio'));
    await tester.pumpAndSettle();

    expect(pushed?.name, AppRoutes.menu);
    expect(pushed?.arguments, '12');
  });

    testWidgets('teclado numérico com tecla de envio', (tester) async {
    await pumpTable(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, const TextInputType.numberWithOptions(signed: true));
    expect(field.textInputAction, TextInputAction.go);
  });

}
