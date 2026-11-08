import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/features/client/order/last_order_store.dart';
import 'package:dinna/features/client/order/order_confirmation_view.dart';
import 'package:dinna/features/client/table/table_view.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/home/temporary_flow_access.dart';
import 'package:dinna/features/menu/menu_view.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_details_view.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:dinna/features/restaurant/orders_queue_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';
import '../restaurant/fake_order_repository.dart';
import '../restaurant/sample_order.dart';
import 'fake_api_status_repository.dart';

void main() {
  testWidgets('a home mantém a identidade e mostra o acesso temporário', (tester) async {
    await _pumpApp(tester);

    expect(find.text('dinna'), findsOneWidget);
    expect(find.text('Pedido à mesa, do seu jeito.'), findsOneWidget);
    expect(find.text('Verificar conexão com a API'), findsOneWidget);
    expect(find.text('API não verificada'), findsOneWidget);
    expect(find.byType(TemporaryFlowAccess), findsOneWidget);
    expect(find.text('Acesso temporário'), findsOneWidget);
    expect(find.text('Remover antes da entrega.'), findsOneWidget);
    expect(find.text('Mesa'), findsOneWidget);
    expect(find.text('Cardápio'), findsOneWidget);
    expect(find.text('Detalhe do produto'), findsOneWidget);
    expect(find.text('Carrinho'), findsOneWidget);
    expect(find.text('Fila de pedidos'), findsOneWidget);
    expect(find.text('pendente'), findsOneWidget);
    expect(find.text('O detalhe do pedido abre ao tocar um item da fila.'), findsOneWidget);
  });

  testWidgets('a home abre a confirmação do último pedido restaurado', (tester) async {
    final order = sampleOrder(id: 'o-history', table: '7');
    final store = MemoryLastOrderStore();
    await store.save(order);
    await _pumpApp(tester, lastOrders: store);
    await tester.pumpAndSettle();

    final button = find.text('Ver último pedido');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('Mesa 7'), findsOneWidget);
    final context = tester.element(find.byType(OrderConfirmationView));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.order);
    expect(ModalRoute.of(context)!.settings.arguments, isA<OrderConfirmationArgs>());
  });

  testWidgets('abre a mesa e volta para a home', (tester) async {
    await _pumpApp(tester);
    await _open(tester, 'Mesa');

    expect(find.byType(TableView), findsOneWidget);
    expect(find.text('Qual é a sua mesa?'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
    final context = tester.element(find.byType(TableView));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.table);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(find.text('dinna'), findsOneWidget);
    expect(find.byType(TemporaryFlowAccess), findsOneWidget);
  });

  testWidgets('o cardápio abre a tela real e o detalhe de produto segue no placeholder', (
    tester,
  ) async {
    final products = FakeProductRepository(() async => ProductList.ready(const []));
    await _pumpApp(tester, products: products);

    await _open(tester, 'Cardápio');
    expect(find.byType(MenuView), findsOneWidget);
    expect(find.text('Cardápio vazio'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
    expect(products.calls, 1);
    expect(products.findCalls, 0);

    // O header do cardápio não tem seta (Figma): volta pelo botão do sistema.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await _open(tester, 'Detalhe do produto');
    expect(find.text(AppRoutes.product), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsOneWidget);
    expect(find.text('Página não encontrada'), findsNothing);
    expect(products.calls, 1);
    expect(products.findCalls, 0);

    final context = tester.element(find.text('Tela ainda não implementada.'));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.product);
  });

  testWidgets('o carrinho abre o estado vazio e segue para o cardápio', (tester) async {
    await _pumpApp(tester);
    await _open(tester, 'Carrinho');

    expect(find.text('Seu carrinho está vazio'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
    final cartContext = tester.element(find.text('Seu carrinho está vazio'));
    expect(ModalRoute.of(cartContext)!.settings.name, AppRoutes.cart);

    await tester.tap(find.text('Ver cardápio'));
    await tester.pumpAndSettle();

    expect(find.byType(MenuView), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
  });

  testWidgets('a fila abre o detalhe de um pedido já existente', (tester) async {
    final order = sampleOrder(id: 'o1', table: '12');
    final orders = FakeOrderRepository(() async => OrderList.ready([order]));
    final products = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]),
    );

    await _pumpApp(tester, orders: orders, products: products);
    await _open(tester, 'Fila de pedidos');

    expect(find.byType(OrdersQueueView), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(orders.calls, 1);
    expect(products.calls, 0);

    await tester.tap(find.text('Mesa 12'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailsView), findsOneWidget);
    expect(find.text('Pedido'), findsOneWidget);
    expect(find.text('Burger Clássico'), findsOneWidget);
    expect(orders.calls, 1);
    expect(products.calls, 1);

    final context = tester.element(find.text('Burger Clássico'));
    final route = ModalRoute.of(context)!;
    expect(route.settings.name, AppRoutes.restaurantOrder);
    final arguments = route.settings.arguments;
    expect(arguments, isA<RestaurantOrderArgs>());
    final selected = arguments! as RestaurantOrderArgs;
    expect(selected.id, const AppRouteId('o1'));
    expect(selected.order, order);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Fila de pedidos'), findsOneWidget);
    expect(find.byType(OrderDetailsView), findsNothing);
  });

  testWidgets('fila sem API mostra o erro já existente', (tester) async {
    final orders = FakeOrderRepository(
      () async => const OrderList.unavailable('Não foi possível carregar a fila'),
    );

    await _pumpApp(tester, orders: orders);
    await _open(tester, 'Fila de pedidos');

    expect(find.byType(OrdersQueueView), findsOneWidget);
    expect(find.text('Não foi possível carregar a fila'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Nenhum pedido na fila'), findsNothing);
    expect(find.byType(OrderDetailsView), findsNothing);
    expect(orders.calls, 1);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  OrderRepository? orders,
  ProductRepository? products,
  LastOrderStore? lastOrders,
}) {
  return tester.pumpWidget(
    DinnaApp(
      key: UniqueKey(),
      apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
      orderRepository: orders ?? FakeOrderRepository(() async => OrderList.ready(const [])),
      productRepository: products ?? FakeProductRepository(() async => ProductList.ready(const [])),
      lastOrderStore: lastOrders,
      pollDelay: pendingPollDelay,
    ),
  );
}

Future<void> _open(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
