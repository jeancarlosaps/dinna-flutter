import 'dart:async';

import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_lines.dart';
import 'package:dinna/features/client/cart/cart_view.dart';
import 'package:dinna/features/client/cart/cart_view_model.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
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

  Future<void> pumpCart(
    WidgetTester tester, {
    required CartLines lines,
    required Future<OrderSubmission> Function({
      required String table,
      required List<CartItem> items,
    })
    onCreate,
    String? table = '12',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: CartView(
          createViewModel: () =>
              CartViewModel(FakeProductRepository(() async => catalog), lines: lines),
          createSubmission: () => OrderSubmissionViewModel(
            FakeOrderRepository(() async => OrderList.ready(const []), onCreate: onCreate),
          ),
          table: table,
          onOpenMenu: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSend(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.tap(button);
  }

  testWidgets('falha definitiva permite tentar de novo e mantém o carrinho', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    final sent = <List<CartItem>>[];
    await pumpCart(
      tester,
      lines: lines,
      onCreate: ({required table, required items}) async {
        sent.add(List<CartItem>.of(items));
        if (sent.length == 1) {
          return const OrderSubmission.failed(
            'Não foi possível enviar o pedido',
            failure: DataFailure.unavailable,
          );
        }
        return OrderSubmission.created(sampleOrder(id: 'o2'));
      },
    );

    await tapSend(tester, 'Enviar pedido');
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.single.quantity, 1);
    expect(find.text('Pedido não enviado'), findsOneWidget);
    expect(find.text('Não foi possível enviar o pedido'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Moqueca de Peixe'), findsOneWidget);
    expect(find.text('sem cebola'), findsOneWidget);
    expect(lines.read().single.quantity, 1);

    await tester.tap(find.byTooltip('Aumentar quantidade'));
    await tester.pump();
    expect(lines.read().single.quantity, 2);

    await tapSend(tester, 'Tentar novamente');
    await tester.pumpAndSettle();

    expect(sent, hasLength(2));
    expect(sent.last.single.quantity, 2);
    expect(sent.last.single.note, 'sem cebola');
    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(find.text('Pedido não enviado'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(lines.read().single.quantity, 2);
  });

  testWidgets('falha incerta não reenvia e pede para conferir', (tester) async {
    final lines = ProcessCartLines([line(2)]);
    var calls = 0;
    await pumpCart(
      tester,
      lines: lines,
      onCreate: ({required table, required items}) async {
        calls++;
        return const OrderSubmission.failed(
          OrderSubmission.uncertainOutcomeMessage,
          failure: DataFailure.uncertain,
          outcomeUncertain: true,
        );
      },
    );

    await tapSend(tester, 'Enviar pedido');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls, 1);
    expect(find.text('Envio sem confirmação'), findsOneWidget);
    expect(find.textContaining(OrderSubmission.uncertainOutcomeMessage), findsOneWidget);
    expect(find.textContaining(OrderSubmissionViewModel.verifyBeforeRetryGuidance), findsOneWidget);
    expect(find.textContaining('falhou'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(find.text('Moqueca de Peixe'), findsOneWidget);
    expect(find.text('sem cebola'), findsOneWidget);
    expect(lines.read().single.quantity, 2);
    expect(lines.read().single.note, 'sem cebola');
  });

  testWidgets('o envio em andamento ignora outro toque', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    final gate = Completer<OrderSubmission>();
    var calls = 0;
    await pumpCart(
      tester,
      lines: lines,
      onCreate: ({required table, required items}) {
        calls++;
        return gate.future;
      },
    );

    await tapSend(tester, 'Enviar pedido');
    await tester.tap(find.text('Enviar pedido'));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Enviando pedido'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.text('Pedido não enviado'), findsNothing);
    expect(lines.read().single.quantity, 1);

    gate.complete(OrderSubmission.created(sampleOrder(id: 'o1')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(find.text('O restaurante recebeu o pedido.'), findsOneWidget);
    expect(find.text('Enviando pedido'), findsNothing);
    expect(lines.read(), hasLength(1));
  });

  testWidgets('o sucesso não limpa o carrinho nem oferece nova tentativa', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    var calls = 0;
    await pumpCart(
      tester,
      lines: lines,
      onCreate: ({required table, required items}) async {
        calls++;
        expect(table, '12');
        expect(items.single.quantity, 1);
        return OrderSubmission.created(sampleOrder(id: 'o1', totalCents: 4890));
      },
    );

    await tapSend(tester, 'Enviar pedido');
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(find.text('O restaurante recebeu o pedido.'), findsOneWidget);
    expect(find.text('Pedido não enviado'), findsNothing);
    expect(find.text('Envio sem confirmação'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(find.text('Moqueca de Peixe'), findsOneWidget);
    expect(lines.read().single.quantity, 1);
    expect(lines.read().single.note, 'sem cebola');
  });

  testWidgets('a mesa da rota entra no envio', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    String? sentTable;
    await tester.pumpWidget(
      DinnaApp(
        apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
        orderRepository: FakeOrderRepository(
          () async => OrderList.ready(const []),
          onCreate: ({required table, required items}) async {
            sentTable = table;
            return OrderSubmission.created(sampleOrder(id: 'o1'));
          },
        ),
        productRepository: FakeProductRepository(() async => catalog),
        cartLines: lines,
        pollDelay: (_) async {},
      ),
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.cart, arguments: ' 7 ');
    await tester.pumpAndSettle();

    await tapSend(tester, 'Enviar pedido');
    await tester.pumpAndSettle();

    expect(sentTable, '7');
    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(lines.read().single.quantity, 1);
  });
}
