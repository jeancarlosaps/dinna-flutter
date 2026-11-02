import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/features/client/order/order_confirmation_view.dart';
import 'package:dinna/features/client/order/order_tracking_view.dart';
import 'package:dinna/features/restaurant/order_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('mostra mesa, itens, quantidades, total e identificação do pedido', (tester) async {
    final order = confirmed();
    await pumpConfirmation(tester, arguments: OrderConfirmationArgs(order: order));

    expect(find.text('Pedido recebido'), findsWidgets);
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
}
