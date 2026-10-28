import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_details_view.dart';
import 'package:dinna/features/restaurant/order_details_view_model.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:dinna/features/restaurant/orders_queue_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home/fake_api_status_repository.dart';
import '../menu/fake_product_repository.dart';
import 'fake_order_repository.dart';
import 'sample_order.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 16, 18);

  Order detailOrder({OrderStatus status = OrderStatus.received, String? secondNote}) {
    return sampleOrder(
      id: 'o1',
      table: '12',
      status: status,
      createdAt: createdAt,
      totalCents: 123456,
      items: [
        OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola'),
        OrderItem(productId: 'p2', quantity: 1, note: secondNote),
      ],
    );
  }

  ProductRepository catalog(List<Product> products) {
    return FakeProductRepository(() async => ProductList.ready(products));
  }

  Future<void> pumpDetails(
    WidgetTester tester, {
    required Object? arguments,
    required ProductRepository products,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    Navigator.of(tester.element(find.byType(Scaffold))).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: AppRoutes.restaurantOrder, arguments: arguments),
        builder: (_) => OrderDetailsView(
          createViewModel: (order) => OrderDetailsViewModel(products, order: order),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra mesa, horário local e status', (tester) async {
    final order = detailOrder(status: OrderStatus.preparing);
    await pumpDetails(
      tester,
      arguments: RestaurantOrderArgs(id: const AppRouteId('o1'), order: order),
      products: catalog([]),
    );

    expect(find.text('Mesa 12'), findsOneWidget);
    expect(find.text(_clock(order.createdAt)), findsOneWidget);
    expect(find.text('Preparando'), findsOneWidget);
    expect(find.text('Recebido'), findsNothing);

    final scheme = Theme.of(tester.element(find.text('Preparando'))).colorScheme;
    expect(tester.widget<Text>(find.text('Preparando')).style?.color, scheme.tertiary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o resumo anuncia mesa, horário e status uma única vez', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      final order = detailOrder();
      await pumpDetails(
        tester,
        arguments: RestaurantOrderArgs(id: const AppRouteId('o1'), order: order),
        products: catalog([]),
      );

      final time = _clock(order.createdAt);
      final summary = 'Mesa 12, $time, Recebido';
      final labels = _semanticsLabels(tester);

      expect(find.text('Mesa 12'), findsOneWidget);
      expect(find.text(time), findsOneWidget);
      expect(find.text('Recebido'), findsOneWidget);
      expect(labels.where((label) => label.contains('Mesa 12')), [summary]);
      expect(labels.where((label) => label == time), isEmpty);
      expect(labels.where((label) => label == 'Recebido'), isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('mostra os itens e as quantidades', (tester) async {
    await pumpDetails(
      tester,
      arguments: RestaurantOrderArgs(id: const AppRouteId('o1'), order: detailOrder()),
      products: catalog([
        sampleProduct(id: 'p1', name: 'Burger Clássico'),
        sampleProduct(id: 'p2', name: 'Suco de laranja'),
      ]),
    );

    expect(find.text('2×'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('Burger Clássico'), findsOneWidget);
    expect(find.text('Suco de laranja'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('R\$ 1.234,56'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resolve o nome pelo catálogo, inclusive o indisponível', (tester) async {
    await pumpDetails(
      tester,
      arguments: RestaurantOrderArgs(id: const AppRouteId('o1'), order: detailOrder()),
      products: catalog([
        sampleProduct(id: 'p1', name: 'Burger Clássico', available: false),
        sampleProduct(id: 'p2', name: 'Suco de laranja'),
      ]),
    );

    expect(find.text('Burger Clássico'), findsOneWidget);
    expect(find.text('Suco de laranja'), findsOneWidget);
    expect(find.text(OrderDetailsViewModel.missingProductName), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mostra a observação só quando o item tem uma', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpDetails(
      tester,
      arguments: RestaurantOrderArgs(id: const AppRouteId('o1'), order: detailOrder()),
      products: catalog([
        sampleProduct(id: 'p1', name: 'Burger Clássico'),
        sampleProduct(id: 'p2', name: 'Suco de laranja'),
      ]),
    );

    expect(find.text('sem cebola'), findsOneWidget);
    expect(find.text('Suco de laranja'), findsOneWidget);
    expect(find.text('null'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('produto fora do catálogo não quebra a tela', (tester) async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]),
    );
    await pumpDetails(
      tester,
      arguments: RestaurantOrderArgs(id: const AppRouteId('o1'), order: detailOrder()),
      products: repository,
    );

    expect(repository.calls, 1);
    expect(find.text('Burger Clássico'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.text(OrderDetailsViewModel.missingProductName), findsOneWidget);
    expect(find.text('sem cebola'), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(find.text('Nomes indisponíveis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falha ao consultar produtos preserva mesa, itens e horário', (tester) async {
    final order = detailOrder(status: OrderStatus.ready);
    final repository = FakeProductRepository(() async => const ProductList.unavailable('sem rede'));
    await pumpDetails(
      tester,
      arguments: RestaurantOrderArgs(id: const AppRouteId('o1'), order: order),
      products: repository,
    );

    expect(repository.calls, 1);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(find.text(_clock(order.createdAt)), findsOneWidget);
    expect(find.text('Pronto'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('sem cebola'), findsOneWidget);
    expect(find.text(OrderDetailsViewModel.unavailableProductName), findsNWidgets(2));
    expect(find.text('Nomes indisponíveis'), findsOneWidget);
    expect(find.text('sem rede'), findsOneWidget);
    expect(find.text('R\$ 1.234,56'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('não consulta o cardápio quando a rota não traz o pedido', (tester) async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]),
    );

    await pumpDetails(tester, arguments: const AppRouteId('pedido-1'), products: repository);

    expect(repository.calls, 0);
    expect(find.text('Pedido indisponível'), findsOneWidget);
    expect(
      find.text('Abra o pedido pela fila para ver a mesa, os itens e o horário.'),
      findsOneWidget,
    );
    expect(find.byType(OrderDetailsView), findsOneWidget);

    final context = tester.element(find.byType(OrderDetailsView));
    expect(ModalRoute.of(context)!.settings.arguments, const AppRouteId('pedido-1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('não abre o pedido quando o id da rota não é o do pedido', (tester) async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]),
    );

    await pumpDetails(
      tester,
      arguments: RestaurantOrderArgs(id: const AppRouteId('outro'), order: detailOrder()),
      products: repository,
    );

    expect(repository.calls, 0);
    expect(find.text('Pedido indisponível'), findsOneWidget);
    expect(find.text('Mesa 12'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('abre o pedido selecionado sem consultar a fila de novo', (tester) async {
    final order = detailOrder();
    final orders = FakeOrderRepository(() async => OrderList.ready([order]));
    final products = FakeProductRepository(
      () async => ProductList.ready([
        sampleProduct(id: 'p1', name: 'Burger Clássico'),
        sampleProduct(id: 'p2', name: 'Suco de laranja'),
      ]),
    );

    await tester.pumpWidget(
      DinnaApp(
        apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
        orderRepository: orders,
        productRepository: products,
        pollDelay: pendingPollDelay,
      ),
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.restaurant);
    await tester.pumpAndSettle();

    expect(find.byType(OrdersQueueView), findsOneWidget);
    expect(orders.calls, 1);
    expect(products.calls, 0);

    await tester.tap(find.text('Mesa 12'));
    await tester.pumpAndSettle();

    expect(find.text('Pedido'), findsOneWidget);
    expect(find.text('Burger Clássico'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('sem cebola'), findsOneWidget);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('volta para a fila com a posição e os pedidos preservados', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 480));

    final orders = [
      for (var index = 0; index < 20; index++)
        sampleOrder(
          id: 'o$index',
          table: '$index',
          createdAt: DateTime.utc(2026, 10, 16, 18, index),
        ),
    ];
    final repository = FakeOrderRepository(() async => OrderList.ready(orders));
    final products = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]),
    );

    await tester.pumpWidget(
      DinnaApp(
        apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
        orderRepository: repository,
        productRepository: products,
        pollDelay: pendingPollDelay,
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.restaurant);
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(offset, greaterThan(0));

    final visibleTables = find.textContaining(RegExp(r'^Mesa \d+$')).hitTestable();
    final table = tester.widget<Text>(visibleTables.first).data!;
    await tester.tap(visibleTables.first);
    await tester.pumpAndSettle();

    expect(find.text('Pedido'), findsOneWidget);
    expect(find.text(table), findsOneWidget);
    expect(repository.calls, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Fila de pedidos'), findsOneWidget);
    expect(find.text('Pedido'), findsNothing);
    expect(find.text(table).hitTestable(), findsOneWidget);
    expect(tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels, offset);
    expect(repository.calls, 2);
    expect(products.calls, 1);
    expect(tester.takeException(), isNull);
  });
}

List<String> _semanticsLabels(WidgetTester tester) {
  final renderView = tester.binding.renderViews.firstWhere(
    (view) => view.flutterView == tester.view,
  );
  final root = renderView.owner!.semanticsOwner!.rootSemanticsNode!;
  final labels = <String>[];
  void visit(SemanticsNode node) {
    final label = node.getSemanticsData().label;
    if (label.isNotEmpty) labels.add(label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return labels;
}

String _clock(DateTime createdAt) {
  final local = createdAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}
