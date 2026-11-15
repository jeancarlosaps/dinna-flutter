import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_repository.dart';
import 'package:dinna/features/client/cart/cart_session.dart';
import 'package:dinna/features/client/order/order_confirmation_view.dart';
import 'package:dinna/features/client/order/order_tracking_view.dart';
import 'package:dinna/features/client/table/table_view.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/menu_view.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/restaurant/order_details_view.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:dinna/features/restaurant/orders_queue_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/home/fake_api_status_repository.dart';
import '../features/menu/fake_product_repository.dart';
import '../features/recommendation/fake_recommendation_repository.dart';
import '../features/restaurant/fake_order_repository.dart';

void main() {
  test('os fluxos não se sobrepõem e o detalhe aponta para rota conhecida', () {
    final client = AppRoutes.clientFlow.toSet();
    final restaurant = AppRoutes.restaurantFlow.toSet();

    expect(client, hasLength(AppRoutes.clientFlow.length));
    expect(restaurant, hasLength(AppRoutes.restaurantFlow.length));
    expect(client.intersection(restaurant), isEmpty);
    expect(client.contains(AppRoutes.home), isFalse);
    expect(restaurant.contains(AppRoutes.home), isFalse);
    expect(client.union(restaurant), containsAll(AppRoutes.detailRoutes));
    expect(AppRoutes.clientFlow.first, AppRoutes.table);
    expect(AppRoutes.restaurantFlow.first, AppRoutes.restaurant);
    expect(AppRoutes.clientFlow.contains(AppRoutes.recommendation), isFalse);
    expect(AppRoutes.restaurantFlow.contains(AppRoutes.recommendation), isFalse);
  });

  testWidgets('abre na home', (tester) async {
    await _pumpApp(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.initialRoute, AppRoutes.home);

    final context = tester.element(find.text('dinna'));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.home);
    expect(find.text('Pedido à mesa, do seu jeito.'), findsOneWidget);
    expect(find.text('Verificar conexão com a API'), findsOneWidget);
  });

  testWidgets('entra no fluxo do cliente pela mesa', (tester) async {
    await _pumpApp(tester);
    await _push(tester, AppRoutes.table);

    expect(find.byType(TableView), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
    expect(find.text('dinna'), findsNothing);

    final context = tester.element(find.byType(TableView));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.table);
  });

  testWidgets('entra no fluxo do restaurante pela fila', (tester) async {
    await _pumpApp(tester);
    await _push(tester, AppRoutes.restaurant);

    expect(find.byType(OrdersQueueView), findsOneWidget);
    expect(find.text('Pedidos'), findsWidgets);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
    expect(find.text('Página não encontrada'), findsNothing);

    final context = tester.element(find.byType(OrdersQueueView));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.restaurant);
  });

  testWidgets('abre o carrinho vazio', (tester) async {
    await _pumpApp(tester);
    await _push(tester, AppRoutes.cart);

    expect(find.text('Seu carrinho'), findsOneWidget);
    expect(find.text('Seu carrinho está vazio'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);

    final context = tester.element(find.text('Seu carrinho está vazio'));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.cart);
  });

  testWidgets('o carrinho devolve a mesa ao cardápio', (tester) async {
    await _pumpApp(tester);
    await _push(tester, AppRoutes.cart, arguments: '12');

    await tester.tap(find.text('Ver cardápio'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuView), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
  });

  testWidgets('navega para o cardápio e volta até a home', (tester) async {
    await _pumpApp(tester);

    final homeContext = tester.element(find.text('dinna'));
    final openedTable = Navigator.of(homeContext).pushNamed(AppRoutes.table);
    await tester.pumpAndSettle();

    await _push(tester, AppRoutes.menu, from: _tableTitle);
    expect(find.byType(MenuView), findsOneWidget);
    expect(find.byType(TableView), findsNothing);

    // O header do cardápio não tem seta (Figma): volta pelo botão do sistema.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TableView), findsOneWidget);

    Navigator.of(tester.element(find.byType(TableView))).pop();
    await tester.pumpAndSettle();

    expect(find.text('dinna'), findsOneWidget);
    expect(await openedTable, isNull);
  });

  testWidgets('navega até o detalhe do restaurante e volta para a fila', (tester) async {
    await _pumpApp(tester);
    await _push(tester, AppRoutes.restaurant);

    final queueContext = tester.element(find.byType(OrdersQueueView));
    final openedOrder = Navigator.of(queueContext)
        .pushNamed(AppRoutes.restaurantOrder, arguments: const AppRouteId('pedido-1'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailsView), findsOneWidget);
    expect(find.text('Pedido indisponível'), findsOneWidget);
    final orderContext = tester.element(find.byType(OrderDetailsView));
    expect(ModalRoute.of(orderContext)!.settings.arguments, const AppRouteId('pedido-1'));

    Navigator.of(orderContext).pop('revisado');
    await tester.pumpAndSettle();

    expect(find.byType(OrdersQueueView), findsOneWidget);
    expect(await openedOrder, 'revisado');
  });

  testWidgets('rota desconhecida mostra a página e volta para a home', (tester) async {
    await _pumpApp(tester);
    await _push(tester, '/desconhecida');

    expect(find.text('Página não encontrada'), findsOneWidget);
    expect(find.text('/desconhecida'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);

    final context = tester.element(find.text('Página não encontrada'));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(find.text('dinna'), findsOneWidget);
    expect(find.text('Verificar conexão com a API'), findsOneWidget);
  });

  testWidgets('nome parecido com rota válida continua desconhecido', (tester) async {
    const unknownNames = <String>[
      '/table/',
      '/menu/extra',
      '/order/tracking/extra',
      '/restaurant/queue',
    ];

    for (final name in unknownNames) {
      await _pumpApp(tester);
      await _push(tester, name);

      expect(find.text('Página não encontrada'), findsOneWidget, reason: name);
      expect(find.text(name), findsOneWidget, reason: name);
      expect(find.text('Tela ainda não implementada.'), findsNothing, reason: name);
    }
  });

  testWidgets('rotas sem tela própria abrem o placeholder', (tester) async {
    final routes = [...AppRoutes.clientFlow, ...AppRoutes.restaurantFlow].where(
      (route) =>
          route != AppRoutes.table &&
          route != AppRoutes.menu &&
          route != AppRoutes.cart &&
          route != AppRoutes.order &&
          route != AppRoutes.orderTracking &&
          route != AppRoutes.restaurant &&
          route != AppRoutes.restaurantOrder &&
          route != AppRoutes.restaurantMenu,
    );

    for (final route in routes) {
      await _pumpApp(tester);
      await _push(tester, route);

      expect(find.text(route), findsOneWidget, reason: route);
      expect(find.text('Tela ainda não implementada.'), findsOneWidget, reason: route);
      expect(find.text('Página não encontrada'), findsNothing, reason: route);
    }
  });

  testWidgets('preserva o id das rotas de detalhe', (tester) async {
    for (final route in AppRoutes.detailRoutes) {
      final id = AppRouteId(route);
      await _pumpApp(tester);
      await _push(tester, route, arguments: id);

      final context = tester.element(
        route == AppRoutes.restaurantOrder
            ? find.byType(OrderDetailsView)
            : route == AppRoutes.orderTracking
            ? find.byType(OrderTrackingView)
            : find.text(route),
      );
      final modalRoute = ModalRoute.of(context)!;
      expect(modalRoute.settings.name, route, reason: route);
      expect(modalRoute.settings.arguments, id, reason: route);
    }
  });

  testWidgets('a confirmação e o acompanhamento sem argumento não consultam a API', (tester) async {
    final orders = FakeOrderRepository(() async => OrderList.ready(const []));
    final products = FakeProductRepository(() async => ProductList.ready(const []));
    await tester.pumpWidget(
      DinnaApp(
        apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
        orderRepository: orders,
        productRepository: products,
        pollDelay: pendingPollDelay,
      ),
    );
    await tester.pumpAndSettle();

    await _push(tester, AppRoutes.order);
    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('Pedido indisponível'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);

    await _push(tester, AppRoutes.orderTracking, from: 'Pedido indisponível');
    expect(find.byType(OrderTrackingView), findsOneWidget);
    expect(find.text('Acompanhamento indisponível'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
    expect(orders.calls, 0);
    expect(orders.createCalls, 0);
    expect(products.calls, 0);
    expect(products.findCalls, 0);
  });

  testWidgets('a home e o GET /health continuam válidos depois de ir e voltar', (tester) async {
    await _pumpApp(tester);
    await _push(tester, AppRoutes.table);
    await _push(tester, AppRoutes.home, from: _tableTitle);

    expect(find.text('API não verificada'), findsOneWidget);

    await tester.tap(find.text('Verificar conexão com a API'));
    await tester.pump();

    expect(find.text('API online'), findsOneWidget);

    Navigator.of(tester.element(find.text('API online'))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(TableView), findsOneWidget);

    Navigator.of(tester.element(find.byType(TableView))).pop();
    await tester.pumpAndSettle();

    expect(find.text('dinna'), findsOneWidget);
    expect(find.text('API não verificada'), findsOneWidget);
  });

  testWidgets('abre Me ajuda a escolher com a mesa do cardápio e volta para ele', (tester) async {
    await _pumpApp(tester);
    await _push(tester, AppRoutes.menu, arguments: '12');

    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
    await tester.tap(find.text('Me ajuda a escolher'));
    await tester.pumpAndSettle();

    expect(find.text('Quanto pretende gastar?'), findsOneWidget);
    final context = tester.element(find.text('Quanto pretende gastar?'));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.recommendation);
    expect(ModalRoute.of(context)!.settings.arguments, '12');

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(MenuView), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(MenuView)))!.settings.arguments, '12');
  });

  testWidgets('cardápio, recomendação e carrinho compartilham a mesma mesa', (tester) async {
    await _pumpApp(tester);
    await _push(tester, AppRoutes.menu, arguments: '12');

    await tester.tap(find.text('Me ajuda a escolher'));
    await tester.pumpAndSettle();
    expect(
      ModalRoute.of(tester.element(find.text('Quanto pretende gastar?')))!.settings.arguments,
      '12',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(MenuView))).pushNamed(AppRoutes.cart, arguments: '12');
    await tester.pumpAndSettle();
    expect(find.text('Seu carrinho'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('Seu carrinho')))!.settings.arguments, '12');

    await tester.tap(find.text('Ver cardápio'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuView), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(MenuView)))!.settings.arguments, '12');
  });

  testWidgets('a sugestão entra no carrinho aberto e a revisão segue na mesma mesa', (
    tester,
  ) async {
    final cartRepository = _RouterCartRepository();
    final session = CartSession(cartRepository);
    final burger = Product(
      id: 'p3',
      name: 'Burger da casa',
      description: 'Descrição interna',
      category: 'burgers',
      priceCents: 1890,
      imageUrl: null,
      available: true,
    );
    final products = FakeProductRepository(
      () async => ProductList.ready([burger]),
      onFindById: (_) async => ProductDetail.ready(burger),
    );

    await tester.pumpWidget(
      DinnaApp(
        apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
        orderRepository: FakeOrderRepository(() async => OrderList.ready(const [])),
        productRepository: products,
        cartSession: session,
        recommendationRepository: FakeRecommendationRepository(
          (_) async => RecommendationAttempt.ready(
            Recommendation(
              provider: RecommendationProvider.answered,
              outcome: RecommendationOutcome.suggestions,
              products: [RecommendationSuggestion(productId: 'p3', reason: 'Carne, Salgado')],
            ),
          ),
        ),
        pollDelay: pendingPollDelay,
      ),
    );
    await tester.pumpAndSettle();
    expect(session.isReady, isTrue);
    expect(session.read(), isEmpty);

    await _push(tester, AppRoutes.menu, arguments: '12');
    await tester.tap(find.text('Me ajuda a escolher'));
    await tester.pumpAndSettle();
    await _tapMenuText(tester, 'Até R\$ 20');
    await _tapMenuText(tester, 'Normal');
    await _tapMenuText(tester, 'Frango');
    await _tapMenuText(tester, 'Equilibrado');
    await _tapMenuText(tester, 'Salgado');
    await _tapMenuText(tester, 'Me sugere um prato');

    expect(find.text('Burger da casa'), findsOneWidget);
    expect(find.text('Carne, Salgado'), findsOneWidget);
    expect(find.text('Adicionar ao carrinho'), findsOneWidget);

    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pumpAndSettle();

    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(session.read().single.productId, 'p3');
    expect(session.read().single.quantity, 1);
    expect(cartRepository.items.single.quantity, 1);

    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Ver carrinho')));
    await tester.pumpAndSettle();

    expect(find.text('Seu carrinho'), findsOneWidget);
    expect(find.text('Burger da casa'), findsWidgets);
    expect(find.text('Enviar pedido'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('Seu carrinho')))!.settings.name, AppRoutes.cart);
    expect(ModalRoute.of(tester.element(find.text('Seu carrinho')))!.settings.arguments, '12');
    expect(session.read().single.lineId, cartRepository.items.single.lineId);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(find.text('Burger da casa'), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.text('Carne, Salgado')))!.settings.arguments, '12');
  });
}

/// Texto da `TableView`, usado como ponto de partida para navegar a partir dela.
const _tableTitle = 'Qual é a sua mesa?';

Future<void> _pumpApp(WidgetTester tester) {
  return tester.pumpWidget(
    DinnaApp(
      key: UniqueKey(),
      apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
      orderRepository: FakeOrderRepository(() async => OrderList.ready(const [])),
      productRepository: FakeProductRepository(() async => ProductList.ready(const [])),
      pollDelay: pendingPollDelay,
    ),
  );
}

Future<void> _push(WidgetTester tester, String route, {String? from, Object? arguments}) async {
  final context = tester.element(find.text(from ?? 'dinna'));
  Navigator.of(context).pushNamed(route, arguments: arguments);
  await tester.pumpAndSettle();
}

Future<void> _tapMenuText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.scrollUntilVisible(finder, 400);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _RouterCartRepository extends CartRepository {
  final items = <CartItem>[];

  @override
  Future<List<CartItem>> load() async => List<CartItem>.of(items);

  @override
  Future<CartItem> add({required String productId, required int quantity, String? note}) async {
    final item = CartItem(
      lineId: 'line-${items.length + 1}',
      productId: productId,
      quantity: quantity,
      note: note,
    );
    items.add(item);
    return item;
  }

  @override
  Future<bool> update(CartItem item) async => false;

  @override
  Future<bool> remove(String lineId) async => false;

  @override
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) async => items;
}
