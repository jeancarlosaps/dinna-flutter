import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/menu_view.dart';
import 'package:dinna/features/menu/menu_view_model.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_product_repository.dart';

Product _product(String id, String name, String category, {bool available = true}) => Product(
  id: id,
  name: name,
  description: '',
  category: category,
  priceCents: 1000,
  imageUrl: null,
  available: available,
);

Future<void> _pumpMenu(WidgetTester tester, List<Product> products, {String? table = '12'}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MenuView(
        table: table,
        createViewModel: () =>
            MenuViewModel(FakeProductRepository(() async => ProductList.ready(products))),
        onOpenCart: (_, _) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra a mesa, as categorias e os produtos', (tester) async {
    await _pumpMenu(tester, [
      _product('1', 'Margherita', 'pizzas'),
      _product('2', 'Suco', 'bebidas', available: false),
    ]);

    expect(find.text('Mesa 12'), findsOneWidget);
    expect(find.text('Margherita'), findsOneWidget);
    expect(find.text('Suco'), findsOneWidget);
    expect(find.text('Esgotado'), findsOneWidget);
  });

  testWidgets('o chip da categoria filtra os produtos', (tester) async {
    await _pumpMenu(tester, [
      _product('1', 'Margherita', 'pizzas'),
      _product('2', 'Suco', 'bebidas'),
    ]);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bebidas'));
    await tester.pumpAndSettle();

    expect(find.text('Suco'), findsOneWidget);
    expect(find.text('Margherita'), findsNothing);
  });

  testWidgets('mostra a mesa que veio da navegação', (tester) async {
    for (final table in ['1', '7', '42']) {
      await _pumpMenu(tester, [_product('1', 'Margherita', 'pizzas')], table: table);

      expect(find.text('Mesa $table'), findsOneWidget);
    }
  });

  testWidgets('sem mesa não mostra o chip da mesa', (tester) async {
    await _pumpMenu(tester, [_product('1', 'Margherita', 'pizzas')], table: null);

    expect(find.textContaining('Mesa'), findsNothing);
  });
}
