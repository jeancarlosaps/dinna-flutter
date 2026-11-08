import 'dart:async';

import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_lines.dart';
import 'package:dinna/features/client/cart/cart_view.dart';
import 'package:dinna/features/client/cart/cart_view_model.dart';
import 'package:dinna/features/client/order/order_confirmation_view.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/client/order/order_tracking_view.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_format.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/fake_api_status_repository.dart';
import '../../menu/fake_product_repository.dart';
import '../../restaurant/fake_order_repository.dart';
import '../../restaurant/sample_order.dart';

void main() {
  final catalog = ProductList.ready([
    Product(
      id: 'p1',
      name: 'Moqueca de Peixe',
      description: '',
      category: 'pratos',
      priceCents: 4890,
      imageUrl: null,
      available: true,
    ),
  ]);

  CartItem line(int quantity) => CartItem(productId: 'p1', quantity: quantity, note: 'sem cebola');

  Order confirmedOrder() {
    return sampleOrder(
      id: 'order-real',
      table: '4',
      totalCents: 2500,
      items: [OrderItem(productId: 'p9', quantity: 1, note: 'sem sal')],
    );
  }

  Future<void> openCart(WidgetTester tester) async {
    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.cart, arguments: '12');
    await tester.pumpAndSettle();
  }

  Widget app({
    required CartLines lines,
    required Future<OrderSubmission> Function({
      required String table,
      required List<CartItem> items,
    })
    onCreate,
    OrderIntentStore? store,
    FakeOrderRepository? orders,
    FakeProductRepository? products,
  }) {
    return DinnaApp(
      apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
      orderRepository:
          orders ?? FakeOrderRepository(() async => OrderList.ready(const []), onCreate: onCreate),
      productRepository: products ?? FakeProductRepository(() async => catalog),
      cartLines: lines,
      orderIntentStore: store,
      pollDelay: (_) async {},
    );
  }

  testWidgets('o 201 gravado abre a confirmação do pedido e não a do carrinho', (tester) async {
    final lines = ProcessCartLines([line(2)]);
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        expect(table, '12');
        expect(items.single.quantity, 2);
        return OrderSubmission.created(confirmedOrder());
      },
    );
    final products = FakeProductRepository(() async => catalog);
    await tester.pumpWidget(
      app(
        lines: lines,
        onCreate: ({required table, required items}) => orders.create(table: table, items: items),
        orders: orders,
        products: products,
      ),
    );
    await tester.pumpAndSettle();
    await openCart(tester);

    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(orders.createCalls, 1);
    expect(orders.calls, 0);
    expect(products.calls, 1);
    expect(products.findCalls, 0);
    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('Mesa 4'), findsOneWidget);
    expect(find.text('Mesa 12'), findsNothing);
    expect(find.text('order-real'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('p9'), findsOneWidget);
    expect(find.text('sem sal'), findsOneWidget);
    expect(find.text(formatOrderTotal(2500)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OrderConfirmationView),
        matching: find.text('Moqueca de Peixe'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(OrderConfirmationView), matching: find.text('2×')),
      findsNothing,
    );
    expect(lines.read(), isEmpty);

    final action = find.text('Acompanhar pedido');
    await tester.scrollUntilVisible(action, 200);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byType(OrderTrackingView), findsOneWidget);
    expect(orders.createCalls, 1);
    expect(products.calls, 1);
    final tracking = ModalRoute.of(tester.element(find.byType(OrderTrackingView)))!;
    expect(tracking.settings.name, AppRoutes.orderTracking);
    expect(tracking.settings.arguments, const AppRouteId('order-real'));
    expect(find.text('Status ao vivo indisponível'), findsOneWidget);

    Navigator.of(tester.element(find.byType(OrderTrackingView))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.byType(OrderTrackingView), findsNothing);
    expect(orders.createCalls, 1);
  });

  testWidgets('dois toques no envio abrem uma confirmação', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    var calls = 0;
    await tester.pumpWidget(
      app(
        lines: lines,
        onCreate: ({required table, required items}) async {
          calls++;
          return OrderSubmission.created(confirmedOrder());
        },
      ),
    );
    await tester.pumpAndSettle();
    await openCart(tester);

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enviar pedido'));
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(lines.read(), isEmpty);
  });

  testWidgets('o 201 repetido não abre outra confirmação nem outro POST', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    var calls = 0;
    final submission = OrderSubmissionViewModel(
      FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async {
          calls++;
          if (calls == 1) {
            return const OrderSubmission.failed(
              OrderSubmission.uncertainOutcomeMessage,
              failure: DataFailure.uncertain,
              outcomeUncertain: true,
            );
          }
          return OrderSubmission.created(confirmedOrder());
        },
      ),
    );
    addTearDown(submission.dispose);
    var opened = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: CartView(
          createViewModel: () =>
              CartViewModel(FakeProductRepository(() async => catalog), lines: lines),
          submission: submission,
          table: '12',
          onOpenMenu: (_) {},
          onOrderConfirmed: (context, order) async {
            opened++;
            await Navigator.of(context)
                .pushNamed(AppRoutes.order, arguments: OrderConfirmationArgs(order: order));
          },
        ),
        onGenerateRoute: (settings) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) {
              if (settings.name == AppRoutes.orderTracking) return const OrderTrackingView();
              return OrderConfirmationView(
                onTrack: (context, order) async {
                  await Navigator.of(context)
                      .pushNamed(AppRoutes.orderTracking, arguments: AppRouteId(order.id));
                },
              );
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderConfirmationView), findsNothing);
    expect(opened, 0);

    await tester.tap(find.text('Reenviar o mesmo pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reenviar'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(calls, 2);
    expect(opened, 1);
    expect(find.byType(OrderConfirmationView), findsOneWidget);

    Navigator.of(tester.element(find.byType(OrderConfirmationView))).pop();
    await tester.pumpAndSettle();
    await submission.resume(submission.intentId!);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(opened, 1);
    expect(find.byType(OrderConfirmationView), findsNothing);
    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(lines.read().single.quantity, 1);
  });

  testWidgets('reiniciar com sucesso gravado recupera a confirmação sem POST', (tester) async {
    final lines = ProcessCartLines([line(2)]);
    final store = MemoryOrderIntentStore();
    var calls = 0;

    await tester.pumpWidget(
      app(
        lines: lines,
        store: store,
        onCreate: ({required table, required items}) async {
          calls++;
          return OrderSubmission.created(confirmedOrder());
        },
      ),
    );
    await tester.pumpAndSettle();
    await openCart(tester);
    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(OrderConfirmationView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    calls = 0;
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        calls++;
        return const OrderSubmission.failed('não deveria enviar');
      },
    );
    await tester.pumpWidget(
      app(lines: lines, store: store, onCreate: orders.create, orders: orders),
    );
    await tester.pumpAndSettle();
    await openCart(tester);

    expect(calls, 0);
    expect(orders.createCalls, 0);
    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('order-real'), findsOneWidget);
    expect(find.text('Mesa 4'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(lines.read(), isEmpty);
    await tester.scrollUntilVisible(find.text('Voltar ao início'), 200);
    expect(find.text('Voltar ao início'), findsOneWidget);
    expect(find.text('Fazer outro pedido'), findsOneWidget);

    final stored = await store.load();
    expect(stored!.order!.id, 'order-real');
    expect(stored.phase.name, 'succeeded');

    Navigator.of(tester.element(find.byType(OrderConfirmationView))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(OrderConfirmationView), findsNothing);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(find.text('dinna'), findsWidgets);
    expect(calls, 0);
    expect((await store.load())!.order!.id, 'order-real');
  });

  testWidgets('resultado incerto não abre confirmação', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    var calls = 0;
    await tester.pumpWidget(
      app(
        lines: lines,
        onCreate: ({required table, required items}) async {
          calls++;
          return const OrderSubmission.failed(
            OrderSubmission.uncertainOutcomeMessage,
            failure: DataFailure.uncertain,
            outcomeUncertain: true,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await openCart(tester);
    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byType(OrderConfirmationView), findsNothing);
    expect(find.text('Envio sem confirmação'), findsOneWidget);
    expect(find.text('Pedido enviado'), findsNothing);
    expect(find.text('Pedido recebido'), findsNothing);
    expect(lines.read().single.quantity, 1);
  });

  testWidgets('falha ao gravar o 201 não apresenta confirmação', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    final store = MemoryOrderIntentStore();
    var calls = 0;
    await tester.pumpWidget(
      app(
        lines: lines,
        store: store,
        onCreate: ({required table, required items}) async {
          calls++;
          store.failNextSave();
          return OrderSubmission.created(confirmedOrder());
        },
      ),
    );
    await tester.pumpAndSettle();
    await openCart(tester);
    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byType(OrderConfirmationView), findsNothing);
    expect(find.text('Pedido enviado'), findsNothing);
    expect(find.text('Pedido recebido'), findsNothing);
    expect(find.text(OrderSubmissionViewModel.terminalNotRecordedMessage), findsOneWidget);
    expect(find.text('Ver confirmação'), findsNothing);
    expect(lines.read().single.quantity, 1);
    expect((await store.load())!.phase.name, 'pending');
  });

  testWidgets('voltar durante o POST não abre a confirmação na tela anterior', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    final gate = Completer<OrderSubmission>();
    var calls = 0;
    await tester.pumpWidget(
      app(
        lines: lines,
        onCreate: ({required table, required items}) {
          calls++;
          return gate.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await openCart(tester);
    await tester.tap(find.text('Enviar pedido'));
    await tester.pump();

    final cart = tester.element(find.byType(CartView));
    Navigator.of(cart).pop();
    await tester.pump();

    final leaving = tester.element(find.byType(CartView, skipOffstage: false));
    final route = ModalRoute.of(leaving)!;
    expect(route.isCurrent, isFalse);
    expect(
      tester.state<State<StatefulWidget>>(find.byType(CartView, skipOffstage: false)).mounted,
      isTrue,
    );

    gate.complete(OrderSubmission.created(confirmedOrder()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls, 1);
    expect(find.byType(OrderConfirmationView, skipOffstage: false), findsNothing);
    expect(find.text('dinna', skipOffstage: false), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(CartView, skipOffstage: false), findsNothing);
    expect(find.byType(OrderConfirmationView, skipOffstage: false), findsNothing);
    expect(calls, 1);

    await openCart(tester);

    expect(calls, 1);
    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('order-real'), findsOneWidget);
    expect(lines.read(), isEmpty);
  });

  testWidgets('falha ao apagar o sucesso mantém o comprovante e bloqueia outro envio', (
    tester,
  ) async {
    final lines = ProcessCartLines([line(1)]);
    final store = MemoryOrderIntentStore();
    final ids = <String>[];
    var calls = 0;
    final submission = OrderSubmissionViewModel(
      FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async {
          calls++;
          return OrderSubmission.created(confirmedOrder());
        },
      ),
      intentStore: store,
      newIntentId: () {
        final id = '00000000-0000-4000-8000-${(ids.length + 1).toString().padLeft(12, '0')}';
        ids.add(id);
        return id;
      },
    );
    addTearDown(submission.dispose);
    var opened = 0;
    Order? shown;

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: CartView(
          createViewModel: () =>
              CartViewModel(FakeProductRepository(() async => catalog), lines: lines),
          submission: submission,
          table: '12',
          onOpenMenu: (_) {},
          onOrderConfirmed: (context, order) async {
            opened++;
            shown = order;
            await Navigator.of(context)
                .pushNamed(AppRoutes.order, arguments: OrderConfirmationArgs(order: order));
          },
        ),
        onGenerateRoute: (settings) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => OrderConfirmationView(onTrack: (_, _) async {}),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(opened, 1);
    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(submission.canViewPersistedConfirmation, isTrue);

    Navigator.of(tester.element(find.byType(OrderConfirmationView))).pop();
    await tester.pumpAndSettle();
    await tester.pump();

    expect(opened, 1);
    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(find.text('Ver confirmação'), findsOneWidget);

    store.failNextSave();
    await tester.tap(find.text('Fazer outro pedido'));
    await tester.pumpAndSettle();

    expect(submission.canViewPersistedConfirmation, isTrue);
    expect(submission.canBeginAnotherOrder, isFalse);
    expect(submission.canRequestSubmit, isFalse);
    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(find.text('Ver confirmação'), findsOneWidget);
    expect(find.text('Fazer outro pedido'), findsNothing);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(calls, 1);
    expect(ids, hasLength(1));
    expect((await store.load())!.phase.name, 'succeeded');

    await tester.tap(find.text('Ver confirmação'));
    await tester.pumpAndSettle();

    expect(opened, 2);
    expect(shown!.id, 'order-real');
    expect(find.text('order-real'), findsOneWidget);
    expect(find.byType(OrderConfirmationView), findsOneWidget);

    await submission.submit(table: '7', items: lines.read());
    await tester.pump();

    expect(calls, 1);
    expect(ids, hasLength(1));
    expect(submission.canRequestSubmit, isFalse);
    expect(find.byType(OrderConfirmationView), findsOneWidget);
  });
}
