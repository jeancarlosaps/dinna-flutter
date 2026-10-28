import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/features/client/table/table_view.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_details_view.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:dinna/features/restaurant/orders_queue_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/home/fake_api_status_repository.dart';
import '../features/menu/fake_product_repository.dart';
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
    expect(find.text('Fila de pedidos'), findsOneWidget);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
    expect(find.text('Página não encontrada'), findsNothing);

    final context = tester.element(find.byType(OrdersQueueView));
    expect(ModalRoute.of(context)!.settings.name, AppRoutes.restaurant);
  });

  testWidgets('navega para o cardápio e volta até a home', (tester) async {
    await _pumpApp(tester);

    final homeContext = tester.element(find.text('dinna'));
    final openedTable = Navigator.of(homeContext).pushNamed(AppRoutes.table);
    await tester.pumpAndSettle();

    await _push(tester, AppRoutes.menu, from: _tableTitle);
    expect(find.text(AppRoutes.menu), findsOneWidget);
    expect(find.byType(TableView), findsNothing);

    await tester.tap(find.byType(BackButton));
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

    final queueContext = tester.element(find.text('Fila de pedidos'));
    final openedOrder = Navigator.of(queueContext)
        .pushNamed(AppRoutes.restaurantOrder, arguments: const AppRouteId('pedido-1'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailsView), findsOneWidget);
    expect(find.text('Pedido indisponível'), findsOneWidget);
    final orderContext = tester.element(find.byType(OrderDetailsView));
    expect(ModalRoute.of(orderContext)!.settings.arguments, const AppRouteId('pedido-1'));

    Navigator.of(orderContext).pop('revisado');
    await tester.pumpAndSettle();

    expect(find.text('Fila de pedidos'), findsOneWidget);
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
          route != AppRoutes.restaurant &&
          route != AppRoutes.restaurantOrder,
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
        route == AppRoutes.restaurantOrder ? find.byType(OrderDetailsView) : find.text(route),
      );
      final modalRoute = ModalRoute.of(context)!;
      expect(modalRoute.settings.name, route, reason: route);
      expect(modalRoute.settings.arguments, id, reason: route);
    }
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
