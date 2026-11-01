import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_lines.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
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

  CartItem line(int quantity, {String? note = 'sem cebola'}) =>
      CartItem(productId: 'p1', quantity: quantity, note: note);

  Future<void> openCart(WidgetTester tester) async {
    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.cart, arguments: '12');
    await tester.pumpAndSettle();
  }

  testWidgets('a confirmação reenvia a mesma tentativa e o cancelamento não envia', (tester) async {
    final lines = ProcessCartLines([line(1)]);
    final sent = <List<CartItem>>[];
    var uncertain = true;
    await tester.pumpWidget(
      _app(
        lines: lines,
        catalog: catalog,
        onCreate: ({required table, required items}) async {
          sent.add(List<CartItem>.of(items));
          if (uncertain) {
            return const OrderSubmission.failed(
              OrderSubmission.uncertainOutcomeMessage,
              failure: DataFailure.uncertain,
              outcomeUncertain: true,
            );
          }
          return OrderSubmission.created(sampleOrder(id: 'o1'));
        },
      ),
    );
    await tester.pumpAndSettle();
    await openCart(tester);

    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aumentar quantidade'));
    await tester.pump();

    expect(lines.read().single.quantity, 2);
    expect(find.text('Reenviar o mesmo pedido'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);

    await tester.tap(find.text('Reenviar o mesmo pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(find.text('Reenviar o mesmo pedido?'), findsNothing);

    uncertain = false;
    await tester.tap(find.text('Reenviar o mesmo pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reenviar'));
    await tester.pumpAndSettle();

    expect(sent, hasLength(2));
    expect(sent.last.single.quantity, 1);
    expect(sent.last.single.note, 'sem cebola');
    expect(find.text('Pedido enviado'), findsOneWidget);
    expect(lines.read().single.quantity, 2);
  });

  testWidgets('reiniciar o app recupera o envio incerto e mantém o carrinho', (tester) async {
    final lines = ProcessCartLines([line(2)]);
    // O binding de widget não conclui arquivo real. A durabilidade do disco
    // está no teste do store e no HTTP local; aqui o app novo lê o mesmo store.
    final store = MemoryOrderIntentStore();
    var calls = 0;

    Future<OrderSubmission> onCreate({required String table, required List<CartItem> items}) async {
      calls++;
      return const OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        outcomeUncertain: true,
      );
    }

    await tester.pumpWidget(_app(lines: lines, catalog: catalog, store: store, onCreate: onCreate));
    await tester.pumpAndSettle();
    await openCart(tester);
    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Envio sem confirmação'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    calls = 0;
    await tester.pumpWidget(_app(lines: lines, catalog: catalog, store: store, onCreate: onCreate));
    await tester.pumpAndSettle();
    await openCart(tester);

    expect(calls, 0);
    expect(find.text('Envio sem confirmação'), findsOneWidget);
    expect(find.textContaining(OrderSubmissionViewModel.verifyBeforeRetryGuidance), findsOneWidget);
    expect(find.text('Enviar pedido'), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
    expect(lines.read().single.quantity, 2);
    expect(lines.read().single.note, 'sem cebola');
  });
}

Widget _app({
  required CartLines lines,
  required ProductList catalog,
  required Future<OrderSubmission> Function({required String table, required List<CartItem> items})
  onCreate,
  OrderIntentStore? store,
}) {
  return DinnaApp(
    apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
    orderRepository: FakeOrderRepository(() async => OrderList.ready(const []), onCreate: onCreate),
    productRepository: FakeProductRepository(() async => catalog),
    cartLines: lines,
    orderIntentStore: store,
    pollDelay: (_) async {},
  );
}
