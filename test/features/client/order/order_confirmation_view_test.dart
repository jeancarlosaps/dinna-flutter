import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/features/client/order/order_confirmation_view.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/client/order/order_tracking_view.dart';
import 'package:dinna/features/restaurant/order_format.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../restaurant/fake_order_repository.dart';
import '../../restaurant/sample_order.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 16, 18);

  Order confirmed({
    String id = 'order-1',
    String table = '12',
    OrderStatus status = OrderStatus.received,
    List<OrderItem>? items,
    int totalCents = 4890,
  }) {
    return sampleOrder(
      id: id,
      table: table,
      status: status,
      createdAt: createdAt,
      totalCents: totalCents,
      items:
          items ??
          [
            OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola'),
            OrderItem(productId: 'p9', quantity: 1, note: null),
          ],
    );
  }

  Future<void> pumpConfirmation(
    WidgetTester tester, {
    required Object? arguments,
    Future<void> Function(BuildContext context, Order order)? onTrack,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    Navigator.of(tester.element(find.byType(Scaffold))).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: AppRoutes.order, arguments: arguments),
        builder: (_) => OrderConfirmationView(
          onTrack:
              onTrack ??
              (context, order) async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: RouteSettings(
                      name: AppRoutes.orderTracking,
                      arguments: AppRouteId(order.id),
                    ),
                    builder: (_) => const OrderTrackingView(),
                  ),
                );
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String appBarTitle(WidgetTester tester) {
    final title = tester.widget<AppBar>(find.byType(AppBar)).title;
    expect(title, isA<Text>());
    return (title! as Text).data!;
  }

  testWidgets('mostra mesa, itens, quantidades, total e identificação do pedido', (tester) async {
    final order = confirmed();
    await pumpConfirmation(tester, arguments: OrderConfirmationArgs(order: order));

    expect(find.text('Pedido recebido'), findsWidgets);
    expect(appBarTitle(tester), 'Pedido recebido');
    expect(find.text('O restaurante recebeu este pedido.'), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(find.text('Recebido'), findsOneWidget);
    expect(find.text(formatOrderTimestamp(order.createdAt)), findsOneWidget);
    expect(find.text('order-1'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('p1'), findsOneWidget);
    expect(find.text('p9'), findsOneWidget);
    expect(find.text('sem cebola'), findsOneWidget);
    final total = find.text(formatOrderTotal(4890));
    await tester.scrollUntilVisible(total, 80);
    expect(total, findsOneWidget);
    expect(find.text('Moqueca de Peixe'), findsNothing);
    expect(find.text(formatOrderTotal(2000)), findsNothing);
    final action = find.text('Acompanhar pedido');
    await tester.scrollUntilVisible(action, 80);
    expect(action, findsOneWidget);
  });

  testWidgets('o status exibido é o do pedido confirmado', (tester) async {
    await pumpConfirmation(
      tester,
      arguments: OrderConfirmationArgs(order: confirmed(status: OrderStatus.preparing)),
    );

    expect(find.text('Preparando'), findsOneWidget);
    expect(find.text('Recebido'), findsNothing);
  });

  testWidgets('argumento ausente ou de outro tipo não confirma pedido', (tester) async {
    final invalid = <Object?>[
      null,
      '12',
      const AppRouteId('order-1'),
      confirmed(),
      RestaurantOrderArgs(id: const AppRouteId('order-1'), order: confirmed()),
    ];

    for (final arguments in invalid) {
      await pumpConfirmation(tester, arguments: arguments);
      expect(find.text('Pedido indisponível'), findsOneWidget, reason: '$arguments');
      expect(appBarTitle(tester), 'Pedido', reason: '$arguments');
      expect(find.text('Pedido recebido'), findsNothing, reason: '$arguments');
      expect(find.text('Acompanhar pedido'), findsNothing, reason: '$arguments');
      expect(find.text('Mesa 12'), findsNothing, reason: '$arguments');
    }
  });

  testWidgets('acompanhar abre uma rota e o segundo toque não empilha outra', (tester) async {
    var tracks = 0;
    await pumpConfirmation(
      tester,
      arguments: OrderConfirmationArgs(order: confirmed()),
      onTrack: (context, order) async {
        tracks++;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: AppRoutes.orderTracking, arguments: AppRouteId(order.id)),
            builder: (_) => const OrderTrackingView(),
          ),
        );
      },
    );

    final action = find.widgetWithText(FilledButton, 'Acompanhar pedido');
    await tester.scrollUntilVisible(action, 80);
    final button = tester.widget<FilledButton>(action);
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();

    expect(tracks, 1);
    expect(find.byType(OrderTrackingView), findsOneWidget);
    final tracking = tester.element(find.byType(OrderTrackingView));
    final route = ModalRoute.of(tracking)!;
    expect(route.settings.name, AppRoutes.orderTracking);
    expect(route.settings.arguments, const AppRouteId('order-1'));
    expect(find.text('order-1'), findsWidgets);
    expect(find.text('Status ao vivo indisponível'), findsOneWidget);
    expect(find.text('Preparando'), findsNothing);
    expect(find.text('Tela ainda não implementada.'), findsNothing);
  });

  testWidgets('acompanhamento sem id não consulta status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: DinnaTheme.light(), home: const OrderTrackingView()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acompanhamento indisponível'), findsOneWidget);
    expect(find.text('Status ao vivo indisponível'), findsNothing);

    for (final arguments in <Object?>[null, 'order-1', const AppRouteId('   '), confirmed()]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: DinnaTheme.light(),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      Navigator.of(tester.element(find.byType(Scaffold))).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: AppRoutes.orderTracking, arguments: arguments),
          builder: (_) => const OrderTrackingView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Acompanhamento indisponível'), findsOneWidget, reason: '$arguments');
      expect(find.text('Status ao vivo indisponível'), findsNothing, reason: '$arguments');
    }
  });

  testWidgets('a confirmação cabe numa tela baixa', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpConfirmation(tester, arguments: OrderConfirmationArgs(order: confirmed()));

    expect(tester.takeException(), isNull);
    final action = find.text('Acompanhar pedido');
    await tester.scrollUntilVisible(action, 80);
    await tester.ensureVisible(action);
    expect(tester.takeException(), isNull);
    expect(action, findsOneWidget);
  });

  testWidgets('intenção antiga explica o carrinho e não volta para o envio', (tester) async {
    final order = confirmed();
    final submission = OrderSubmissionViewModel(
      FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async => OrderSubmission.created(order),
      ),
      intentStore: MemoryOrderIntentStore(),
      newIntentId: () => '00000000-0000-4000-8000-0000000000aa',
    );
    addTearDown(submission.dispose);
    await submission.submit(
      table: '12',
      items: [CartItem(productId: 'p1', quantity: 2, note: 'sem cebola')],
    );
    submission.noteLegacyCartRemaining(true);
    var another = 0;

    await tester.pumpWidget(MaterialApp(theme: DinnaTheme.light(), home: const SizedBox.shrink()));
    Navigator.of(tester.element(find.byType(SizedBox))).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: AppRoutes.order,
          arguments: OrderConfirmationArgs(order: order),
        ),
        builder: (_) => OrderConfirmationView(
          onTrack: (_, _) async {},
          onGoHome: (_) {},
          onStartAnother: (_) async => another++,
          submission: submission,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pedido recebido'), findsWidgets);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(tester.widget<AppBar>(find.byType(AppBar)).automaticallyImplyLeading, isFalse);
    await tester.scrollUntilVisible(find.text(OrderSubmissionViewModel.legacyCartMessage), 80);
    expect(find.text(OrderSubmissionViewModel.legacyCartMessage), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Rever carrinho'), 80);
    await tester.tap(find.text('Rever carrinho'));
    await tester.pumpAndSettle();

    expect(another, 1);
    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('Enviar pedido'), findsNothing);
  });

  testWidgets('falha ao iniciar outro pedido aparece na confirmação', (tester) async {
    final order = confirmed();
    final store = MemoryOrderIntentStore();
    final submission = OrderSubmissionViewModel(
      FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async => OrderSubmission.created(order),
      ),
      intentStore: store,
      newIntentId: () => '00000000-0000-4000-8000-0000000000aa',
    );
    addTearDown(submission.dispose);
    await submission.submit(
      table: '12',
      items: [CartItem(productId: 'p1', quantity: 2, note: 'sem cebola')],
    );

    await tester.pumpWidget(MaterialApp(theme: DinnaTheme.light(), home: const SizedBox.shrink()));
    Navigator.of(tester.element(find.byType(SizedBox))).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: AppRoutes.order,
          arguments: OrderConfirmationArgs(order: order),
        ),
        builder: (_) => OrderConfirmationView(
          onTrack: (_, _) async {},
          onGoHome: (_) {},
          onStartAnother: (_) => submission.beginAnotherOrder(),
          submission: submission,
        ),
      ),
    );
    await tester.pumpAndSettle();
    store.failNextSave();
    await tester.scrollUntilVisible(find.text('Fazer outro pedido'), 80);
    await tester.tap(find.text('Fazer outro pedido'));
    await tester.pumpAndSettle();

    expect(find.text('Pedido recebido'), findsWidgets);
    expect(find.text(OrderSubmissionViewModel.unreadableIntentMessage), findsOneWidget);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(submission.canRequestSubmit, isFalse);
    expect(submission.canViewPersistedConfirmation, isTrue);
  });
}
