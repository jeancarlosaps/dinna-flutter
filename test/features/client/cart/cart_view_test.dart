import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_lines.dart';
import 'package:dinna/features/client/cart/cart_view.dart';
import 'package:dinna/features/client/cart/cart_view_model.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_format.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/fake_api_status_repository.dart';
import '../../menu/fake_product_repository.dart';
import '../../restaurant/fake_order_repository.dart';

void main() {
  Product priced(String id, String name, int priceCents) {
    return Product(
      id: id,
      name: name,
      description: '',
      category: 'pratos',
      priceCents: priceCents,
      imageUrl: null,
      available: true,
    );
  }

  final catalog = ProductList.ready([
    priced('p1', 'Moqueca de Peixe', 4890),
    priced('p2', 'Salada Grega', 2690),
  ]);

  CartItem line(String productId, int quantity, [String? note]) {
    return CartItem(productId: productId, quantity: quantity, note: note);
  }

  Future<void> pumpCart(
    WidgetTester tester, {
    required CartLines lines,
    ProductList? products,
    void Function(BuildContext context)? onOpenMenu,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: CartView(
          createViewModel: () => CartViewModel(
            FakeProductRepository(() async => products ?? ProductList.ready(const [])),
            lines: lines,
          ),
          createSubmission: () => OrderSubmissionViewModel(
            FakeOrderRepository(
              () async => OrderList.ready(const []),
              onCreate: ({required table, required items}) async =>
                  const OrderSubmission.failed('Não foi possível enviar o pedido'),
            ),
          ),
          onOpenMenu: onOpenMenu ?? (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra o estado vazio e abre o cardápio', (tester) async {
    var opened = 0;
    await pumpCart(tester, lines: ProcessCartLines(), onOpenMenu: (_) => opened++);

    expect(find.text('Seu carrinho está vazio'), findsOneWidget);
    expect(
      find.text(
        'Escolha os pratos no cardápio e eles aparecem aqui para você revisar antes de enviar.',
      ),
      findsOneWidget,
    );
    expect(find.text('Total estimado'), findsNothing);
    expect(find.text('Taxa de serviço'), findsNothing);

    await tester.tap(find.text('Ver cardápio'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('o estado vazio rola até o cardápio em tela baixa', (tester) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var opened = 0;
    await pumpCart(tester, lines: ProcessCartLines(), onOpenMenu: (_) => opened++);

    final button = find.text('Ver cardápio');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('o preço da linha cabe em tela estreita com texto ampliado', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpCart(
      tester,
      lines: ProcessCartLines([line('p1', 1)]),
      products: catalog,
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text(formatOrderTotal(4890)), findsWidgets);
    expect(find.text('Total estimado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alterar a quantidade atualiza o preço da linha e o total', (tester) async {
    final lines = ProcessCartLines([line('p1', 2, 'sem cebola'), line('p2', 1)]);
    await pumpCart(tester, lines: lines, products: catalog);

    expect(find.text('2 itens'), findsOneWidget);
    expect(find.text('Moqueca de Peixe'), findsOneWidget);
    expect(find.text('sem cebola'), findsOneWidget);
    expect(find.text(formatOrderTotal(9780)), findsOneWidget);
    expect(find.text(formatOrderTotal(12470)), findsOneWidget);

    await tester.tap(find.byTooltip('Aumentar quantidade').first);
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    expect(find.text(formatOrderTotal(14670)), findsOneWidget);
    expect(find.text(formatOrderTotal(17360)), findsOneWidget);
    expect(lines.read().first.quantity, 3);
    expect(lines.read().first.note, 'sem cebola');
    expect(lines.read().last.quantity, 1);
  });

  testWidgets('remover um item atualiza o carrinho e o último item esvazia', (tester) async {
    final lines = ProcessCartLines([line('p1', 1), line('p2', 1)]);
    await pumpCart(tester, lines: lines, products: catalog);

    await tester.tap(find.text('Remover').first);
    await tester.pump();

    expect(find.text('Moqueca de Peixe'), findsNothing);
    expect(find.text('Salada Grega'), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text(formatOrderTotal(2690)), findsWidgets);
    expect(lines.read(), hasLength(1));

    await tester.tap(find.text('Remover'));
    await tester.pump();

    expect(find.text('Seu carrinho está vazio'), findsOneWidget);
    expect(find.text('Total estimado'), findsNothing);
    expect(lines.read(), isEmpty);
  });

  testWidgets('a revisão permanece ao reabrir a rota no mesmo processo', (tester) async {
    final lines = ProcessCartLines([line('p1', 1)]);
    await tester.pumpWidget(
      DinnaApp(
        apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
        orderRepository: FakeOrderRepository(() async => OrderList.ready(const [])),
        productRepository: FakeProductRepository(() async => catalog),
        cartLines: lines,
        pollDelay: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.cart);
    await tester.pumpAndSettle();
    expect(find.text(formatOrderTotal(4890)), findsWidgets);

    await tester.tap(find.byTooltip('Aumentar quantidade'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.text(formatOrderTotal(9780)), findsWidgets);

    Navigator.of(tester.element(find.text('Seu carrinho'))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.cart);
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text(formatOrderTotal(9780)), findsWidgets);
    expect(lines.read().single.quantity, 2);
  });
}
