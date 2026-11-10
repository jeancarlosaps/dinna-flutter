import 'dart:async';

import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/features/client/order/order_status_tracker.dart';
import 'package:dinna/features/client/order/order_tracking_view.dart';
import 'package:dinna/features/client/order/order_tracking_view_model.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../restaurant/controllable_delay.dart';
import '../../restaurant/fake_order_repository.dart';
import '../../restaurant/sample_order.dart';

void main() {
  late ControllableDelay delay;

  setUp(() => delay = ControllableDelay());

  Future<FakeOrderRepository> pumpTracker(
    WidgetTester tester,
    Future<OrderLookup> Function(String id) onFind, {
    double textScale = 1,
  }) async {
    final repository = FakeOrderRepository(() async => OrderList.ready(const []), onFind: onFind);
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              OrderStatusTracker(
                createViewModel: () =>
                    OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return repository;
  }

  testWidgets('mostra os passos e acompanha a mudança de status', (tester) async {
    var status = OrderStatus.received;
    await pumpTracker(tester, (id) async => OrderLookup.ready(sampleOrder(id: id, status: status)));

    expect(find.text('O restaurante recebeu seu pedido.'), findsOneWidget);
    for (final label in ['Recebido', 'Preparando', 'Pronto', 'Finalizado']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('O status atualiza sozinho.'), findsOneWidget);

    status = OrderStatus.ready;
    delay.elapse();
    await tester.pump();
    await tester.pump();

    expect(find.text('Seu pedido está pronto e já vai para a mesa.'), findsOneWidget);
  });

  testWidgets('pedido finalizado mostra a despedida e para de atualizar', (tester) async {
    final repository = await pumpTracker(
      tester,
      (id) async => OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.finished)),
    );

    expect(find.text('Pedido finalizado. Bom apetite!'), findsOneWidget);
    expect(find.text('O status atualiza sozinho.'), findsNothing);
    expect(delay.durations, isEmpty);
    expect(repository.findCalls, 1);
  });

  testWidgets('erro inicial oferece nova tentativa', (tester) async {
    var fail = true;
    await pumpTracker(tester, (id) async {
      if (fail) return const OrderLookup.unavailable('Sem conexão');
      return OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.preparing));
    });

    expect(find.text('Não foi possível consultar o pedido'), findsOneWidget);
    expect(find.text('Sem conexão'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Seu pedido está sendo preparado.'), findsOneWidget);
  });

  testWidgets('falha na atualização mantém o status e avisa', (tester) async {
    var fail = false;
    await pumpTracker(tester, (id) async {
      if (fail) return const OrderLookup.unavailable('Sem conexão');
      return OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.preparing));
    });

    fail = true;
    delay.elapse();
    await tester.pump();
    await tester.pump();

    expect(find.text('Seu pedido está sendo preparado.'), findsOneWidget);
    expect(find.text(OrderStatusTracker.refreshFailureMessage), findsOneWidget);
  });

  testWidgets('pedido inexistente avisa sem nova tentativa', (tester) async {
    await pumpTracker(
      tester,
      (_) async =>
          const OrderLookup.unavailable('Pedido não encontrado', failure: DataFailure.notFound),
    );

    expect(find.text('Pedido não encontrado'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsNothing);
  });

  testWidgets('leitor de tela anuncia o status atual', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTracker(
      tester,
      (id) async => OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.preparing)),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel(RegExp('^Status do pedido: Preparando')))
        .getSemanticsData();
    expect(data.flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
  });

  testWidgets('cabe com texto a 200% numa tela pequena', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpTracker(
      tester,
      (id) async => OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.ready)),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Seu pedido está pronto e já vai para a mesa.'), findsOneWidget);
  });

  testWidgets('app em segundo plano pausa e a volta consulta na hora', (tester) async {
    final repository = await pumpTracker(
      tester,
      (id) async => OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.preparing)),
    );
    expect(repository.findCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    delay.elapse();
    await tester.pump();
    await tester.pump();
    expect(repository.findCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(repository.findCalls, 2);
  });

  testWidgets('outra tela por cima pausa e voltar consulta na hora', (tester) async {
    final observer = RouteObserver<PageRoute<dynamic>>();
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onFind: (id) async => OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.preparing)),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        navigatorObservers: [observer],
        home: Scaffold(
          body: ListView(
            children: [
              OrderStatusTracker(
                routeObserver: observer,
                createViewModel: () =>
                    OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.findCalls, 1);

    final navigator = Navigator.of(tester.element(find.byType(OrderStatusTracker)));
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Text('outra tela'))));
    await tester.pumpAndSettle();
    delay.elapse();
    await tester.pump();
    await tester.pump();
    expect(repository.findCalls, 1);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(repository.findCalls, 2);
  });

  testWidgets('acompanhamento mostra o número público, consulta pelo id e não exibe o UUID', (
    tester,
  ) async {
    const id = 'o_6dbadd42-c7e1-4790-8f96-4d60620ad1fa';
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onFind: (orderId) async =>
          OrderLookup.ready(sampleOrder(id: orderId, orderNumber: 5, status: OrderStatus.received)),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    Navigator.of(tester.element(find.byType(Scaffold))).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: AppRoutes.orderTracking,
          arguments: OrderTrackingArgs(id: AppRouteId(id), orderNumber: 5),
        ),
        builder: (_) => OrderTrackingView(
          createViewModel: (orderId) =>
              OrderTrackingViewModel(repository, orderId: orderId, delay: delay.call),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.lastFoundId, id);
    expect(find.text('Pedido #0005'), findsOneWidget);
    expect(find.textContaining(id), findsNothing);
    expect(find.text('O restaurante recebeu seu pedido.'), findsOneWidget);
    expect(find.text('Status ao vivo indisponível'), findsNothing);
  });
}
