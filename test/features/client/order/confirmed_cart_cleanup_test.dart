import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/features/client/cart/cart_repository.dart';
import 'package:dinna/features/client/cart/cart_session.dart';
import 'package:dinna/features/client/order/confirmed_cart_cleanup.dart';
import 'package:dinna/features/client/order/order_intent.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../restaurant/fake_order_repository.dart';
import '../../restaurant/sample_order.dart';

void main() {
  const intentId = '00000000-0000-4000-8000-0000000000aa';

  CartItem line({int quantity = 2, String? note = 'sem cebola'}) =>
      CartItem(lineId: 'line-1', productId: 'p1', quantity: quantity, note: note);

  Future<void> settle(CartSession session) => session.restore();

  test('sucesso gravado esvazia o carrinho e o reinício não o recupera', () async {
    final repository = _MemoryCart([line()]);
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final store = MemoryOrderIntentStore();
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'order-1')),
    );
    final submission = OrderSubmissionViewModel(
      orders,
      intentStore: store,
      newIntentId: () => intentId,
    );
    addTearDown(submission.dispose);
    final cleanup = ConfirmedCartCleanup(submission: submission, session: session)..attach();
    addTearDown(cleanup.detach);

    await submission.submit(table: '12', items: session.read());
    await settle(session);

    expect(orders.createCalls, 1);
    expect(submission.shouldClearCart, isTrue);
    expect(session.read(), isEmpty);
    expect(repository.confirmedCalls, 1);

    final restarted = CartSession(repository);
    addTearDown(restarted.dispose);
    await restarted.restore();
    final stored = await store.load();

    expect(restarted.read(), isEmpty);
    expect(stored!.phase, OrderIntentPhase.succeeded);
    expect(stored.order!.id, 'order-1');
    expect(stored.id, intentId);
  });

  test('HTTP 401 e timeout não esvaziam o carrinho nem trocam a chave', () async {
    final repository = _MemoryCart([line()]);
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final store = MemoryOrderIntentStore();
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        return const OrderSubmission.failed(
          OrderSubmission.unauthorizedRejectionMessage,
          retainsIntent: true,
        );
      },
    );
    final submission = OrderSubmissionViewModel(
      orders,
      intentStore: store,
      newIntentId: () => intentId,
    );
    addTearDown(submission.dispose);
    final cleanup = ConfirmedCartCleanup(submission: submission, session: session)..attach();
    addTearDown(cleanup.detach);

    await submission.submit(table: '12', items: session.read());
    await settle(session);

    expect(orders.createCalls, 1);
    expect(submission.authRejected, isTrue);
    expect(submission.outcomeUncertain, isFalse);
    expect(submission.shouldClearCart, isFalse);
    expect(session.read().single.quantity, 2);
    expect((await store.load())!.id, intentId);
    expect((await store.load())!.rejection, OrderIntentRejection.unauthorized);

    await submission.submit(table: '12', items: [line(quantity: 1, note: null)]);
    await settle(session);
    expect(orders.createCalls, 1);
    expect(session.read().single.quantity, 2);

    await submission.resume(intentId);
    await settle(session);
    expect(orders.createCalls, 2);
    expect(orders.lastIdempotencyKey, intentId);
    expect(orders.lastBody?['items'], [
      {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
    ]);
    expect(session.read().single.quantity, 2);

    final timeoutOrders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        return const OrderSubmission.failed(
          OrderSubmission.uncertainOutcomeMessage,
          failure: DataFailure.uncertain,
          outcomeUncertain: true,
        );
      },
    );
    final timeout = OrderSubmissionViewModel(
      timeoutOrders,
      intentStore: MemoryOrderIntentStore(),
      newIntentId: () => '00000000-0000-4000-8000-0000000000bb',
    );
    addTearDown(timeout.dispose);
    final timeoutCart = CartSession(_MemoryCart([line()]));
    addTearDown(timeoutCart.dispose);
    await timeoutCart.restore();
    final timeoutCleanup = ConfirmedCartCleanup(submission: timeout, session: timeoutCart)
      ..attach();
    addTearDown(timeoutCleanup.detach);
    await timeout.submit(table: '12', items: timeoutCart.read());
    await timeoutCart.restore();

    expect(timeout.outcomeUncertain, isTrue);
    expect(timeout.shouldClearCart, isFalse);
    expect(timeoutCart.read().single.quantity, 2);
    expect(timeout.intentId, '00000000-0000-4000-8000-0000000000bb');
    expect(timeoutOrders.createCalls, 1);
  });
}

class _MemoryCart implements CartRepository {
  _MemoryCart(List<CartItem> items) : items = List<CartItem>.of(items);

  List<CartItem> items;
  var confirmedCalls = 0;

  @override
  Future<List<CartItem>> load() async => List<CartItem>.unmodifiable(items);

  @override
  Future<CartItem> add({required String productId, required int quantity, String? note}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> update(CartItem item) => throw UnimplementedError();

  @override
  Future<bool> remove(String lineId) => throw UnimplementedError();

  @override
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) async {
    confirmedCalls++;
    items = withoutConfirmedItems(items, confirmedItems).toList();
    return List<CartItem>.unmodifiable(items);
  }
}
