import 'package:dinna/app/theme/dinna_theme.dart';
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

  testWidgets('erro e cardápio vazio cabem numa tela de 360 por 220', (tester) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          createViewModel: () => MenuViewModel(
            FakeProductRepository(() async {
              calls++;
              return const ProductList.unavailable('Sem conexão');
            }),
          ),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Não foi possível carregar o cardápio'), findsOneWidget);
    final retry = find.text('Tentar de novo');
    await tester.scrollUntilVisible(retry, 40);
    expect(retry, findsOneWidget);
    expect(tester.getRect(retry).bottom, lessThanOrEqualTo(220));

    await tester.tap(retry);
    await tester.pump();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cardápio vazio cabe numa tela de 360 por 220', (tester) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          createViewModel: () =>
              MenuViewModel(FakeProductRepository(() async => ProductList.ready(const []))),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final emptyTitle = find.text('Cardápio vazio');
    await tester.scrollUntilVisible(emptyTitle, 40);
    expect(emptyTitle, findsOneWidget);
    final emptyMessage = find.text('O restaurante ainda não cadastrou pratos.');
    await tester.scrollUntilVisible(emptyMessage, 40);
    expect(emptyMessage, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chips acompanham texto ampliado a 200%', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: MenuView(
          table: '12',
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([_product('1', 'Margherita', 'pizzas')]),
            ),
          ),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final chip = tester.renderObject<RenderBox>(find.widgetWithText(ChoiceChip, 'Todos'));
    final strip = tester.renderObject<RenderBox>(find.byType(SingleChildScrollView).first);
    final chipTop = chip.localToGlobal(Offset.zero).dy;
    final stripTop = strip.localToGlobal(Offset.zero).dy;
    expect(chip.size.height, greaterThan(32));
    expect(chipTop, greaterThanOrEqualTo(stripTop - 0.5));
    expect(chipTop + chip.size.height, lessThanOrEqualTo(stripTop + strip.size.height + 0.5));

    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(-80, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pizzas'));
    await tester.pumpAndSettle();
    expect(find.text('Margherita'), findsOneWidget);
  });

  testWidgets('nome do produto acompanha texto ampliado a 300%', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: MenuView(
          table: '12',
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([
                _product('1', 'Moqueca', 'pratos'),
                _product('2', 'Suco', 'bebidas', available: false),
              ]),
            ),
          ),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final name = tester.renderObject<RenderBox>(find.text('Moqueca'));
    final card = tester.renderObject<RenderBox>(find.byType(Card).first);
    final nameTop = name.localToGlobal(Offset.zero).dy;
    final cardTop = card.localToGlobal(Offset.zero).dy;
    expect(name.size.height, greaterThan(40));
    expect(nameTop, greaterThanOrEqualTo(cardTop - 0.5));
    expect(nameTop + name.size.height, lessThanOrEqualTo(cardTop + card.size.height + 0.5));
    await tester.scrollUntilVisible(
      find.text('Esgotado'),
      80,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Esgotado'), findsWidgets);
    expect(find.text('R\$ 10,00'), findsWidgets);
  });
}
