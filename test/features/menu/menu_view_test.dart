import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_repository.dart';
import 'package:dinna/features/client/cart/cart_session.dart';
import 'package:dinna/features/menu/menu_view.dart';
import 'package:dinna/features/menu/menu_view_model.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/shared/widgets/dinna_logo.dart';
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
  testWidgets('a barra mostra quantidade e total e abre o carrinho da mesa', (tester) async {
    final repository = _MutableMenuCart([
      CartItem(lineId: 'line-1', productId: '1', quantity: 2, note: null),
    ]);
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();

    String? openedTable;
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          table: '12',
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([
                _product('1', 'Margherita', 'pizzas'),
                _product('2', 'Suco', 'bebidas'),
              ]),
            ),
          ),
          cartSession: session,
          onOpenCart: (_, table) => openedTable = table,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ver carrinho · 2 itens · R\$ 20,00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Ver carrinho · 2 itens · R\$ 20,00'));
    await tester.pump();
    expect(openedTable, '12');

    await session.addLine(productId: '2', quantity: 1);
    await tester.pump();
    expect(find.text('Ver carrinho · 3 itens · R\$ 30,00'), findsOneWidget);

    await session.removeLine('line-1');
    await tester.pump();
    expect(find.text('Ver carrinho · 1 item · R\$ 10,00'), findsOneWidget);

    await session.removeLine('line-2');
    await tester.pump();
    expect(find.textContaining('Ver carrinho'), findsNothing);
  });

  testWidgets('carrinho vazio não mostra a barra do cardápio', (tester) async {
    final session = CartSession(_MutableMenuCart(const []));
    addTearDown(session.dispose);
    await session.restore();

    await tester.pumpWidget(
      MaterialApp(
        home: MenuView(
          table: '7',
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([_product('1', 'Margherita', 'pizzas')]),
            ),
          ),
          cartSession: session,
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Margherita'), findsOneWidget);
    expect(find.textContaining('Ver carrinho'), findsNothing);
  });

  testWidgets('a barra do carrinho cabe com texto ampliado', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = CartSession(
      _MutableMenuCart([CartItem(lineId: 'line-1', productId: '1', quantity: 2, note: null)]),
    );
    addTearDown(session.dispose);
    await session.restore();

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
          cartSession: session,
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ver carrinho · 2 itens · R\$ 20,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('categorias rolam numa tela baixa com carrinho e recomendação', (tester) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = CartSession(
      _MutableMenuCart([CartItem(lineId: 'line-1', productId: '1', quantity: 1, note: null)]),
    );
    addTearDown(session.dispose);
    await session.restore();

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          table: '12',
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([
                _product('1', 'Margherita', 'pizzas'),
                _product('2', 'Suco', 'bebidas'),
              ]),
            ),
          ),
          cartSession: session,
          onOpenCart: (_, _) {},
          onOpenRecommendation: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    final cartButton = find.widgetWithText(FilledButton, 'Ver carrinho · 1 item · R\$ 10,00');
    expect(cartButton, findsOneWidget);
    expect(tester.getRect(cartButton).bottom, lessThanOrEqualTo(220));

    final menuScroll = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(find.text('Suco'), 40, scrollable: menuScroll);
    expect(find.text('Suco'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('falha ao restaurar o carrinho oferece nova tentativa no cardápio', (tester) async {
    final repository = _MenuCartRepository()..failLoad = true;
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await expectLater(session.restore(), throwsStateError);

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([_product('1', 'Margherita', 'pizzas')]),
            ),
          ),
          onOpenCart: (_, _) {},
          cartSession: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível recuperar o carrinho salvo.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Margherita'), findsOneWidget);

    repository.failLoad = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(session.isReady, isTrue);
    expect(find.text('Não foi possível recuperar o carrinho salvo.'), findsNothing);
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
    final mesa = tester.renderObject<RenderBox>(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == 'Mesa 12'),
    );
    final appBar = tester.renderObject<RenderBox>(find.byType(AppBar));
    final mesaTop = mesa.localToGlobal(Offset.zero).dy;
    final barTop = appBar.localToGlobal(Offset.zero).dy;
    final mesaLeft = mesa.localToGlobal(Offset.zero).dx;
    final barLeft = appBar.localToGlobal(Offset.zero).dx;
    expect(appBar.size.height, greaterThan(56));
    expect(mesaTop, greaterThanOrEqualTo(barTop - 0.5));
    expect(mesaTop + mesa.size.height, lessThanOrEqualTo(barTop + appBar.size.height + 0.5));
    expect(mesaLeft, greaterThanOrEqualTo(barLeft - 0.5));
    expect(mesaLeft + mesa.size.width, lessThanOrEqualTo(barLeft + appBar.size.width + 0.5));

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
      scrollable: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    final sold = find.byWidgetPredicate((widget) => widget is Text && widget.data == 'Esgotado');
    final soldBox = tester.renderObject<RenderBox>(sold);
    final soldCard = tester.renderObject<RenderBox>(
      find.ancestor(of: sold, matching: find.byType(Card)),
    );
    final soldTop = soldBox.localToGlobal(Offset.zero).dy;
    final soldLeft = soldBox.localToGlobal(Offset.zero).dx;
    final soldCardTop = soldCard.localToGlobal(Offset.zero).dy;
    final cardLeft = soldCard.localToGlobal(Offset.zero).dx;
    expect(soldTop, greaterThanOrEqualTo(soldCardTop - 0.5));
    expect(
      soldTop + soldBox.size.height,
      lessThanOrEqualTo(soldCardTop + soldCard.size.height + 0.5),
    );
    expect(soldLeft, greaterThanOrEqualTo(cardLeft - 0.5));
    expect(soldLeft + soldBox.size.width, lessThanOrEqualTo(cardLeft + soldCard.size.width + 0.5));
    expect(find.text('R\$ 10,00'), findsWidgets);
  });

  testWidgets('a marca cabe no header sem mesa com texto a 300%', (tester) async {
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
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([_product('1', 'Moqueca', 'pratos')]),
            ),
          ),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final logo = tester.renderObject<RenderBox>(find.byType(DinnaLogo));
    final appBar = tester.renderObject<RenderBox>(find.byType(AppBar));
    final logoTop = logo.localToGlobal(Offset.zero).dy;
    final barTop = appBar.localToGlobal(Offset.zero).dy;
    expect(appBar.size.height, greaterThan(56));
    expect(logoTop, greaterThanOrEqualTo(barTop - 0.5));
    expect(logoTop + logo.size.height, lessThanOrEqualTo(barTop + appBar.size.height + 0.5));
  });

  testWidgets('o cardápio respeita o recorte lateral da tela', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(left: 40, right: 24);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          table: '12',
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([_product('1', 'Moqueca', 'pratos')]),
            ),
          ),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final chip = tester.renderObject<RenderBox>(find.widgetWithText(ChoiceChip, 'Todos'));
    final chipLeft = chip.localToGlobal(Offset.zero).dx;
    final chipRight = chipLeft + chip.size.width;
    expect(chipLeft, greaterThanOrEqualTo(40));
    expect(chipRight, lessThanOrEqualTo(800 - 24));
  });

  testWidgets('mesa longa cabe no header com texto a 300%', (tester) async {
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
          table: '999999999',
          createViewModel: () => MenuViewModel(
            FakeProductRepository(
              () async => ProductList.ready([_product('1', 'Moqueca', 'pratos')]),
            ),
          ),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final mesa = tester.renderObject<RenderBox>(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == 'Mesa 999999999'),
    );
    final appBar = tester.renderObject<RenderBox>(find.byType(AppBar));
    final mesaTop = mesa.localToGlobal(Offset.zero).dy;
    final mesaLeft = mesa.localToGlobal(Offset.zero).dx;
    final barTop = appBar.localToGlobal(Offset.zero).dy;
    final barLeft = appBar.localToGlobal(Offset.zero).dx;
    expect(mesaTop, greaterThanOrEqualTo(barTop - 0.5));
    expect(mesaTop + mesa.size.height, lessThanOrEqualTo(barTop + appBar.size.height + 0.5));
    expect(mesaLeft, greaterThanOrEqualTo(barLeft - 0.5));
    expect(mesaLeft + mesa.size.width, lessThanOrEqualTo(barLeft + appBar.size.width + 0.5));
  });
}

class _MutableMenuCart implements CartRepository {
  _MutableMenuCart(List<CartItem> seed) : items = List<CartItem>.of(seed), _next = seed.length + 1;

  List<CartItem> items;
  int _next;

  @override
  Future<List<CartItem>> load() async => List<CartItem>.unmodifiable(items);

  @override
  Future<CartItem> add({required String productId, required int quantity, String? note}) async {
    final item = CartItem(
      lineId: 'line-${_next++}',
      productId: productId,
      quantity: quantity,
      note: note,
    );
    items = [...items, item];
    return item;
  }

  @override
  Future<bool> update(CartItem item) async => false;

  @override
  Future<bool> remove(String lineId) async {
    final next = items.where((item) => item.lineId != lineId).toList();
    final removed = next.length != items.length;
    items = next;
    return removed;
  }

  @override
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) async =>
      List<CartItem>.unmodifiable(items);
}

class _MenuCartRepository implements CartRepository {
  bool failLoad = false;

  @override
  Future<List<CartItem>> load() async {
    if (failLoad) throw StateError('SQLite indisponível');
    return const [];
  }

  @override
  Future<CartItem> add({required String productId, required int quantity, String? note}) async =>
      CartItem(lineId: 'line-1', productId: productId, quantity: quantity, note: note);

  @override
  Future<bool> update(CartItem item) async => false;

  @override
  Future<bool> remove(String lineId) async => false;

  @override
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) async => const [];
}
