import 'dart:async';

import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:dinna/features/restaurant/orders_queue_view.dart';
import 'package:dinna/features/restaurant/orders_queue_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controllable_delay.dart';
import 'fake_order_repository.dart';
import 'sample_order.dart';

void main() {
  Future<void> pumpQueue(
    WidgetTester tester,
    OrdersQueueViewModel Function() create, {
    void Function(BuildContext context, Order order)? onOrderSelected,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: OrdersQueueView(createViewModel: create, onOrderSelected: onOrderSelected),
      ),
    );
  }

  testWidgets('mostra o carregamento enquanto a primeira consulta não termina', (tester) async {
    final gate = Completer<OrderList>();
    await pumpQueue(
      tester,
      () => OrdersQueueViewModel(FakeOrderRepository(() => gate.future), delay: pendingPollDelay),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Nenhum pedido na fila'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mostra a fila vazia', (tester) async {
    await pumpQueue(
      tester,
      () => OrdersQueueViewModel(
        FakeOrderRepository(() async => OrderList.ready(const [])),
        delay: pendingPollDelay,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nenhum pedido na fila'), findsOneWidget);
    expect(find.text('Quando um cliente enviar um pedido, ele aparece aqui.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mostra o erro e o retry volta a exibir a fila', (tester) async {
    final order = sampleOrder(id: 'o1', table: '12');
    Completer<OrderList>? retry;
    var calls = 0;
    final repository = FakeOrderRepository(() {
      calls++;
      if (calls == 1) return Future.value(const OrderList.unavailable('sem rede'));
      final gate = Completer<OrderList>();
      retry = gate;
      return gate.future;
    });

    await pumpQueue(tester, () => OrdersQueueViewModel(repository, delay: pendingPollDelay));
    await tester.pumpAndSettle();

    expect(find.text('sem rede'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('sem rede'), findsNothing);

    retry!.complete(OrderList.ready([order]));
    await tester.pumpAndSettle();

    expect(find.text('Mesa 12'), findsOneWidget);
    expect(find.text('Recebido'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o card expõe o toque que abre o pedido', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      Order? selected;
      await pumpQueue(
        tester,
        () => OrdersQueueViewModel(
          FakeOrderRepository(() async => OrderList.ready([sampleOrder(id: 'o1', table: '12')])),
          delay: pendingPollDelay,
        ),
        onOrderSelected: (context, order) => selected = order,
      );
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(Card));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.getSemanticsData().label, contains('Abrir detalhes'));

      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();

      expect(selected?.id, 'o1');
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('mostra mesa, horário e status na ordem da fila', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final older = sampleOrder(
      id: 'o1',
      table: '4',
      status: OrderStatus.preparing,
      createdAt: DateTime.utc(2026, 10, 16, 18),
    );
    final newer = sampleOrder(
      id: 'o2',
      table: '12',
      status: OrderStatus.received,
      createdAt: DateTime.utc(2026, 10, 16, 18, 5),
    );

    await pumpQueue(
      tester,
      () => OrdersQueueViewModel(
        FakeOrderRepository(() async => OrderList.ready([newer, older])),
        delay: pendingPollDelay,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mais antigos primeiro'), findsOneWidget);
    expect(find.text('Mesa 4'), findsOneWidget);
    expect(find.text('Preparando'), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(find.text('Recebido'), findsOneWidget);
    expect(find.text(_clock(older.createdAt)), findsOneWidget);
    expect(find.text(_clock(newer.createdAt)), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Mesa 4')).dy,
      lessThan(tester.getTopLeft(find.text('Mesa 12')).dy),
    );

    final scheme = Theme.of(tester.element(find.text('Preparando'))).colorScheme;
    expect(tester.widget<Text>(find.text('Preparando')).style?.color, scheme.tertiary);
    expect(tester.widget<Text>(find.text('Recebido')).style?.color, scheme.primary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mantém os pedidos na tela quando a atualização falha', (tester) async {
    final order = sampleOrder(id: 'o1', table: '4', status: OrderStatus.ready);
    final gates = <Completer<OrderList>>[];
    final repository = FakeOrderRepository(() {
      final gate = Completer<OrderList>();
      gates.add(gate);
      return gate.future;
    });
    final delay = ControllableDelay();

    await pumpQueue(tester, () => OrdersQueueViewModel(repository, delay: delay.call));
    await tester.pump();
    gates.single.complete(OrderList.ready([order]));
    await tester.pumpAndSettle();

    expect(find.text('Mesa 4'), findsOneWidget);
    expect(find.text('Pronto'), findsOneWidget);

    delay.elapse();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(gates, hasLength(2));

    gates[1].complete(const OrderList.unavailable('sem rede'));
    await tester.pumpAndSettle();

    expect(find.text('Mesa 4'), findsOneWidget);
    expect(find.text('Pronto'), findsOneWidget);
    expect(find.text('sem rede'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rola a lista e limita a largura', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final orders = [
      for (var index = 0; index < 12; index++)
        sampleOrder(
          id: 'o$index',
          table: '$index',
          createdAt: DateTime.utc(2026, 10, 16, 18, index),
        ),
    ];

    await tester.binding.setSurfaceSize(const Size(320, 480));
    await pumpQueue(
      tester,
      () => OrdersQueueViewModel(
        FakeOrderRepository(() async => OrderList.ready(orders)),
        delay: pendingPollDelay,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mesa 0'), findsOneWidget);
    final narrowCard = tester.getSize(find.byType(Card).first).width;
    expect(narrowCard, lessThan(320));
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pump();
    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pump();

    final wideCard = tester.getSize(find.byType(Card).first).width;
    expect(wideCard, greaterThan(600));
    expect(wideCard, lessThanOrEqualTo(720));
    expect(tester.takeException(), isNull);
  });

  testWidgets('suspende o polling fora da rota e atualiza ao voltar', (tester) async {
    final repository = FakeOrderRepository(
      () async => OrderList.ready([sampleOrder(id: 'o1', table: '3')]),
    );
    final delay = ControllableDelay();
    final observer = RouteObserver<PageRoute<dynamic>>();

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        navigatorObservers: [observer],
        onGenerateRoute: (settings) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) {
              return switch (settings.name) {
                AppRoutes.restaurant => OrdersQueueView(
                  createViewModel: () => OrdersQueueViewModel(repository, delay: delay.call),
                  routeObserver: observer,
                ),
                '/' => const Scaffold(body: Text('inicio')),
                _ => const Scaffold(body: Text('detalhe')),
              };
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('inicio'))).pushNamed(AppRoutes.restaurant);
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(find.text('Mesa 3'), findsOneWidget);

    Navigator.of(tester.element(find.text('Fila de pedidos'))).pushNamed('/detalhe');
    await tester.pumpAndSettle();
    expect(find.text('detalhe'), findsOneWidget);

    delay.elapse();
    await tester.pump();
    expect(repository.calls, 1);

    Navigator.of(tester.element(find.text('detalhe'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Fila de pedidos'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('atualiza ao voltar do segundo plano', (tester) async {
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final repository = FakeOrderRepository(
      () async => OrderList.ready([sampleOrder(id: 'o1', table: '5')]),
    );
    final delay = ControllableDelay();

    await pumpQueue(tester, () => OrdersQueueViewModel(repository, delay: delay.call));
    await tester.pumpAndSettle();
    expect(repository.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    delay.elapse();
    await tester.pump();
    expect(repository.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(repository.calls, 2);
    expect(find.text('Mesa 5'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

String _clock(DateTime createdAt) {
  final local = createdAt.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}
