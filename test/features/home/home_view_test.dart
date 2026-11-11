import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/features/client/order/last_order_store.dart';
import 'package:dinna/features/client/order/order_confirmation_view.dart';
import 'package:dinna/features/client/table/table_view.dart';
import 'package:dinna/features/home/api_status_repository.dart';
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
  testWidgets('a home mostra a marca, as entradas e o card da API', (tester) async {
    await _pumpApp(tester);

    expect(find.text('dinna'), findsOneWidget);
    expect(find.text('Pedido à mesa, do seu jeito.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sou cliente'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Restaurante'), findsOneWidget);
    expect(find.text('API não verificada'), findsOneWidget);
    expect(find.text('Verificar conexão com a API'), findsOneWidget);
  });

  testWidgets('a home não mostra atalhos temporários', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Acesso temporário'), findsNothing);
    expect(find.text('Remover antes da entrega.'), findsNothing);
    expect(find.text('pendente'), findsNothing);
    expect(find.text('Cardápio'), findsNothing);
    expect(find.text('Carrinho'), findsNothing);
    expect(find.text('Detalhe do produto'), findsNothing);
    expect(find.text('Fila de pedidos'), findsNothing);
  });

  testWidgets('as entradas cabem com texto a 200% numa tela pequena', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final store = MemoryLastOrderStore();
    await store.save(sampleOrder(id: 'o-history', table: '7'));
    await _pumpApp(tester, lastOrders: store);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in ['Sou cliente', 'Restaurante', 'Ver último pedido']) {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
    }
    expect(find.text('Verificar conexão com a API').hitTestable(), findsOneWidget);
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

  testWidgets('a home abre uma única confirmação com ativações rápidas', (tester) async {
    final order = sampleOrder(id: 'o-history', table: '7');
    final store = MemoryLastOrderStore();
    await store.save(order);
    await _pumpApp(tester, lastOrders: store);
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('Ver último pedido'), matching: find.byType(OutlinedButton)),
    );
    final onPressed = button.onPressed!;
    onPressed();
    onPressed();
    await tester.pumpAndSettle();

    expect(find.byType(OrderConfirmationView), findsOneWidget);
    final context = tester.element(find.byType(OrderConfirmationView));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(find.byType(OrderConfirmationView), findsNothing);
    expect(find.text('dinna'), findsOneWidget);
  });

  testWidgets('a home reabre o último pedido pelo número público sem novo POST', (tester) async {
    const id = 'o_56fd0ea0-1111-4111-8111-111111111111';
    final stored = sampleOrder(id: id, table: '9');
    final store = MemoryLastOrderStore();
    await store.save(stored);
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'nao-deve')),
      onFind: (foundId) async {
        expect(foundId, id);
        return OrderLookup.ready(stored.withOrderNumber(5));
      },
    );

    await _pumpApp(tester, orders: orders, lastOrders: store);
    await tester.pumpAndSettle();

    expect(orders.createCalls, 0);
    expect(orders.findCalls, 1);
    expect(orders.calls, 0);
    expect(find.text('Mesa 9 · Pedido #0005'), findsOneWidget);
    expect(find.textContaining(id), findsNothing);
    expect((await store.load())!.orderNumber, 5);

    final button = find.text('Ver último pedido');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('Pedido #0005'), findsOneWidget);
    expect(find.textContaining(id), findsNothing);
    expect(orders.createCalls, 0);
    expect(orders.findCalls, 1);
  });

  testWidgets('Sou cliente abre a identificação da mesa e volta para a home', (tester) async {
    await _pumpApp(tester);
    await _open(tester, 'Sou cliente');

    expect(find.byType(TableView), findsOneWidget);
    expect(find.text('Qual é a sua mesa?'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
    final context = tester.element(find.byType(TableView));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.table);

    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    expect(find.text('dinna'), findsOneWidget);
    expect(find.text('Sou cliente'), findsOneWidget);
  });

  testWidgets('Restaurante abre a fila e o detalhe de um pedido existente', (tester) async {
    final order = sampleOrder(id: 'o1', table: '12');
    final orders = FakeOrderRepository(() async => OrderList.ready([order]));
    final products = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]),
    );

    await _pumpApp(tester, orders: orders, products: products);
    await _open(tester, 'Restaurante');

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
    await _open(tester, 'Restaurante');

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
