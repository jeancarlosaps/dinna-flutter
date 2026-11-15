import 'dart:async';
import 'dart:io';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/features/client/order/last_order_session.dart';
import 'package:dinna/features/client/order/last_order_store.dart';
import 'package:dinna/features/client/order/order_intent.dart';
import 'package:dinna/features/client/order/order_intent_id.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../restaurant/fake_order_repository.dart';
import '../../restaurant/sample_order.dart';

void main() {
  final items = [CartItem(productId: 'p1', quantity: 2, note: 'sem cebola')];

  OrderSubmissionViewModel viewModelOf(
    Future<OrderSubmission> Function({required String table, required List<CartItem> items}) create,
  ) {
    return OrderSubmissionViewModel(
      FakeOrderRepository(() async => OrderList.ready(const []), onCreate: create),
    );
  }

  test('começa sem envio e sem pedir limpeza do carrinho', () {
    final viewModel = viewModelOf(
      ({required table, required items}) async => OrderSubmission.created(sampleOrder(id: 'o1')),
    );

    expect(viewModel.status, OrderSubmissionStatus.idle);
    expect(viewModel.canRequestSubmit, isTrue);
    expect(viewModel.isSubmitting, isFalse);
    expect(viewModel.order, isNull);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
    expect(viewModel.outcomeUncertain, isFalse);
    expect(viewModel.isDefiniteFailure, isFalse);
    expect(viewModel.confirmedItems, isNull);
    expect(viewModel.confirmedTable, isNull);
    expect(viewModel.shouldClearCart, isFalse);
  });

  test('fica em envio até o 201 e expõe o pedido da API', () async {
    final completer = Completer<OrderSubmission>();
    final order = sampleOrder(id: 'o1', totalCents: 10470);
    final viewModel = viewModelOf(({required table, required items}) {
      expect(table, '12');
      expect(items.single.note, 'sem cebola');
      return completer.future;
    });
    final states = <OrderSubmissionStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    final pending = viewModel.submit(table: '12', items: items);

    expect(viewModel.status, OrderSubmissionStatus.submitting);
    expect(viewModel.isSubmitting, isTrue);
    expect(viewModel.canRequestSubmit, isFalse);
    expect(viewModel.order, isNull);
    expect(viewModel.shouldClearCart, isFalse);
    expect(items, hasLength(1));

    completer.complete(OrderSubmission.created(order));
    await pending;

    expect(states, [OrderSubmissionStatus.submitting, OrderSubmissionStatus.succeeded]);
    expect(viewModel.isSubmitting, isFalse);
    expect(viewModel.order, same(order));
    expect(viewModel.order!.status.name, 'received');
    expect(viewModel.order!.totalCents, 10470);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
    expect(viewModel.outcomeUncertain, isFalse);
    expect(viewModel.isDefiniteFailure, isFalse);
    expect(viewModel.confirmedTable, '12');
    expect(viewModel.confirmedItems, items);
    expect(viewModel.shouldClearCart, isTrue);
    expect(viewModel.canRequestSubmit, isFalse);
    expect(items.single.quantity, 2);
  });

  test('grava o pedido confirmado no histórico independente da intenção', () async {
    final order = sampleOrder(id: 'o-history');
    final store = MemoryLastOrderStore();
    final session = LastOrderSession(store);
    final viewModel = OrderSubmissionViewModel(
      FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async => OrderSubmission.created(order),
      ),
      lastOrderSession: session,
    );
    addTearDown(session.dispose);
    addTearDown(viewModel.dispose);

    await viewModel.submit(table: '12', items: items);

    expect(viewModel.status, OrderSubmissionStatus.succeeded);
    expect(session.order, order);
    expect(session.isPersisted(order), isTrue);
    expect(await store.load(), order);
    expect(viewModel.canBeginAnotherOrder, isTrue);
  });

  test('notifica quando o retry do histórico libera outro pedido', () async {
    final order = sampleOrder(id: 'o-history-retry');
    final store = MemoryLastOrderStore()..failNextSave();
    final session = LastOrderSession(store);
    final viewModel = OrderSubmissionViewModel(
      FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async => OrderSubmission.created(order),
      ),
      lastOrderSession: session,
    );
    addTearDown(session.dispose);
    addTearDown(viewModel.dispose);

    await viewModel.submit(table: '12', items: items);
    expect(session.isPersisted(order), isFalse);
    expect(viewModel.canBeginAnotherOrder, isFalse);

    var notifications = 0;
    viewModel.addListener(() => notifications++);
    await session.retry();

    expect(session.isPersisted(order), isTrue);
    expect(viewModel.canBeginAnotherOrder, isTrue);
    expect(notifications, greaterThan(0));
  });

  test('reconstrói o histórico a partir de uma intenção concluída guardada', () async {
    final order = sampleOrder(id: 'o-recovered');
    final intentStore = MemoryOrderIntentStore();
    final latestOrderStore = MemoryLastOrderStore();
    final session = LastOrderSession(latestOrderStore);
    final now = DateTime.utc(2026, 11, 7, 12);
    final intent = OrderIntent.pending(
      id: newOrderIntentId(),
      createdAt: now.subtract(const Duration(minutes: 1)),
      table: '12',
      items: [
        {'productId': 'p1', 'quantity': 2},
      ],
    ).succeeded(order);
    await intentStore.save(intent);
    final viewModel = OrderSubmissionViewModel(
      FakeOrderRepository(() async => OrderList.ready(const [])),
      intentStore: intentStore,
      lastOrderSession: session,
      now: () => now,
    );
    addTearDown(session.dispose);
    addTearDown(viewModel.dispose);

    await viewModel.restore();

    expect(viewModel.status, OrderSubmissionStatus.succeeded);
    expect(session.isPersisted(order), isTrue);
    expect(await latestOrderStore.load(), order);
    expect(viewModel.canViewPersistedConfirmation, isTrue);
    expect(viewModel.canBeginAnotherOrder, isTrue);
  });

  test('não grava de novo um pedido já persistido ao restaurar a intenção', () async {
    final order = sampleOrder(id: 'o-already-persisted');
    final backingStore = MemoryLastOrderStore();
    await backingStore.save(order);
    final latestOrderStore = _CountingLastOrderStore(backingStore);
    final session = LastOrderSession(latestOrderStore);
    final intentStore = MemoryOrderIntentStore();
    final now = DateTime.utc(2026, 11, 7, 12);
    final intent = OrderIntent.pending(
      id: newOrderIntentId(),
      createdAt: now.subtract(const Duration(minutes: 1)),
      table: '12',
      items: [
        {'productId': 'p1', 'quantity': 2},
      ],
    ).succeeded(order);
    await intentStore.save(intent);
    final viewModel = OrderSubmissionViewModel(
      FakeOrderRepository(() async => OrderList.ready(const [])),
      intentStore: intentStore,
      lastOrderSession: session,
      now: () => now,
    );
    addTearDown(session.dispose);
    addTearDown(viewModel.dispose);

    await viewModel.restore();

    expect(latestOrderStore.saveCalls, 0);
    expect(session.isPersisted(order), isTrue);
    expect(viewModel.canBeginAnotherOrder, isTrue);
  });

  test('validação falha sem limpar o carrinho', () async {
    final viewModel = viewModelOf(
      ({required table, required items}) async =>
          const OrderSubmission.failed('Informe a mesa', failure: DataFailure.validation),
    );

    await viewModel.submit(table: '', items: items);

    expect(viewModel.status, OrderSubmissionStatus.failed);
    expect(viewModel.order, isNull);
    expect(viewModel.errorMessage, 'Informe a mesa');
    expect(viewModel.failure, DataFailure.validation);
    expect(viewModel.outcomeUncertain, isFalse);
    expect(viewModel.isDefiniteFailure, isTrue);
    expect(viewModel.canRequestSubmit, isTrue);
    expect(viewModel.confirmedItems, isNull);
    expect(viewModel.shouldClearCart, isFalse);
    expect(items, hasLength(1));
  });

  test('erro confirmado pela API não pede limpeza nem é incerto', () async {
    final conflict = viewModelOf(
      ({required table, required items}) async =>
          const OrderSubmission.failed('Pedido em conflito', failure: DataFailure.conflict),
    );
    final server = viewModelOf(
      ({required table, required items}) async =>
          const OrderSubmission.failed('Erro interno', failure: DataFailure.unavailable),
    );

    await conflict.submit(table: '12', items: items);
    await server.submit(table: '12', items: items);

    expect(conflict.failure, DataFailure.conflict);
    expect(conflict.outcomeUncertain, isFalse);
    expect(conflict.isDefiniteFailure, isTrue);
    expect(conflict.confirmedItems, isNull);
    expect(conflict.shouldClearCart, isFalse);
    expect(conflict.errorMessage, 'Pedido em conflito');
    expect(server.isDefiniteFailure, isTrue);
    expect(server.outcomeUncertain, isFalse);
    expect(server.shouldClearCart, isFalse);
    expect(server.errorMessage, 'Erro interno');
    expect(items, hasLength(1));
  });

  test('alteração posterior ao submit fica fora da fotografia confirmada', () async {
    final gate = Completer<OrderSubmission>();
    final sent = CartItem(productId: 'p1', quantity: 2, note: 'sem cebola');
    final cart = <CartItem>[sent];
    List<CartItem>? received;
    String? receivedTable;
    final viewModel = viewModelOf(({required table, required items}) {
      receivedTable = table;
      received = items;
      cart.add(CartItem(productId: 'p2', quantity: 1, note: null));
      cart[0] = CartItem(productId: 'p1', quantity: 5, note: 'sem cebola');
      return gate.future;
    });

    final pending = viewModel.submit(table: '12', items: cart);
    await Future<void>.delayed(Duration.zero);
    expect(received, isNot(same(cart)));
    expect(receivedTable, '12');
    expect(received, [sent]);
    expect(viewModel.confirmedItems, isNull);
    expect(viewModel.shouldClearCart, isFalse);

    gate.complete(OrderSubmission.created(sampleOrder(id: 'o1', totalCents: 10470)));
    await pending;

    expect(viewModel.shouldClearCart, isTrue);
    expect(viewModel.confirmedTable, '12');
    expect(viewModel.confirmedItems, [sent]);
    expect(viewModel.confirmedItems!.single.quantity, 2);
    expect(cart, hasLength(2));
    expect(cart.first.quantity, 5);
    expect(cart.last.productId, 'p2');
  });

  test('tempo esgotado não afirma que o pedido falhou e não limpa o carrinho', () async {
    final viewModel = viewModelOf(
      ({required table, required items}) async => const OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        detail: 'Connection reset by peer',
        outcomeUncertain: true,
      ),
    );

    await viewModel.submit(table: '12', items: items);

    expect(viewModel.status, OrderSubmissionStatus.failed);
    expect(viewModel.order, isNull);
    expect(viewModel.outcomeUncertain, isTrue);
    expect(viewModel.isDefiniteFailure, isFalse);
    expect(viewModel.failure, DataFailure.uncertain);
    expect(viewModel.confirmedItems, isNull);
    expect(viewModel.confirmedTable, isNull);
    expect(viewModel.shouldClearCart, isFalse);
    expect(viewModel.errorMessage, OrderSubmission.uncertainOutcomeMessage);
    expect(viewModel.canRequestSubmit, isFalse);
    expect(viewModel.errorMessage, contains('pode ter sido registrado'));
    expect(viewModel.errorMessage, isNot(contains('Connection reset')));
    expect(viewModel.errorMessage, isNot(contains('não foi criado')));
    expect(viewModel.errorMessage, isNot(contains('não foi registrado')));
    expect(viewModel.errorMessage, isNot(contains('falhou')));
    expect(items, hasLength(1));
  });

  test('mensagem vazia de incerteza usa o texto do contrato', () async {
    final viewModel = viewModelOf(
      ({required table, required items}) async => const OrderSubmission.failed(
        '   ',
        failure: DataFailure.uncertain,
        outcomeUncertain: true,
      ),
    );

    await viewModel.submit(table: '12', items: items);

    expect(viewModel.errorMessage, OrderSubmission.uncertainOutcomeMessage);
    expect(viewModel.outcomeUncertain, isTrue);
    expect(viewModel.isDefiniteFailure, isFalse);
    expect(viewModel.confirmedItems, isNull);
    expect(viewModel.shouldClearCart, isFalse);
  });

  test('ignora um segundo envio enquanto o primeiro não terminou', () async {
    final gate = Completer<OrderSubmission>();
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) => gate.future,
    );
    final viewModel = OrderSubmissionViewModel(repository);

    final first = viewModel.submit(table: '12', items: items);
    final second = viewModel.submit(table: '12', items: items);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.isSubmitting, isTrue);
    expect(repository.createCalls, 1);

    gate.complete(OrderSubmission.created(sampleOrder(id: 'o1')));
    await first;
    await second;

    expect(repository.createCalls, 1);
    expect(viewModel.status, OrderSubmissionStatus.succeeded);
    expect(viewModel.shouldClearCart, isTrue);
  });

  test('não repete o POST sozinho e só envia de novo quando pedido', () async {
    var fail = true;
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        if (fail) {
          return const OrderSubmission.failed(
            OrderSubmission.uncertainOutcomeMessage,
            failure: DataFailure.uncertain,
            outcomeUncertain: true,
          );
        }
        return OrderSubmission.created(sampleOrder(id: 'o2', totalCents: 10470));
      },
    );
    final viewModel = OrderSubmissionViewModel(repository);

    await viewModel.submit(table: '12', items: items);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(repository.createCalls, 1);
    expect(viewModel.outcomeUncertain, isTrue);
    expect(viewModel.shouldClearCart, isFalse);
    expect(items, hasLength(1));

    fail = false;
    await viewModel.resume(viewModel.intentId!);

    expect(repository.createCalls, 2);
    expect(viewModel.status, OrderSubmissionStatus.succeeded);
    expect(viewModel.outcomeUncertain, isFalse);
    expect(viewModel.order!.id, 'o2');
    expect(viewModel.shouldClearCart, isTrue);
    expect(items, hasLength(1));
  });

  test('não notifica de novo se a tela for descartada durante o envio', () async {
    final completer = Completer<OrderSubmission>();
    final viewModel = viewModelOf(({required table, required items}) => completer.future);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.submit(table: '12', items: items);
    expect(notifications, 1);

    viewModel.dispose();
    completer.complete(OrderSubmission.created(sampleOrder(id: 'o1')));
    await pending;

    expect(notifications, 1);
    expect(viewModel.status, OrderSubmissionStatus.submitting);
    expect(viewModel.order, isNull);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.shouldClearCart, isFalse);
  });

  test('submit depois do dispose não envia nem notifica', () async {
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final viewModel = OrderSubmissionViewModel(repository);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    viewModel.dispose();
    await viewModel.submit(table: '12', items: items);

    expect(repository.createCalls, 0);
    expect(notifications, 0);
    expect(viewModel.status, OrderSubmissionStatus.idle);
    expect(viewModel.order, isNull);
    expect(viewModel.shouldClearCart, isFalse);
  });

  test('exceção inesperada não confirma rejeição nem limpa o carrinho', () async {
    const detalheInterno = 'falha interna do repository';
    final errors = <Object>[StateError(detalheInterno), const HttpException('conexao encerrada')];

    for (final error in errors) {
      var calls = 0;
      final repository = FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async {
          calls++;
          throw error;
        },
      );
      final viewModel = OrderSubmissionViewModel(repository);
      final states = <OrderSubmissionStatus>[];
      viewModel.addListener(() => states.add(viewModel.status));

      await viewModel.submit(table: '12', items: items);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, 1);
      expect(repository.createCalls, 1);
      expect(states, [OrderSubmissionStatus.submitting, OrderSubmissionStatus.failed]);
      expect(viewModel.order, isNull);
      expect(viewModel.errorMessage, OrderSubmission.uncertainOutcomeMessage);
      expect(viewModel.errorMessage, isNot(contains(detalheInterno)));
      expect(viewModel.errorMessage, isNot(contains('conexao encerrada')));
      expect(viewModel.failure, DataFailure.uncertain);
      expect(viewModel.outcomeUncertain, isTrue);
      expect(viewModel.isDefiniteFailure, isFalse);
      expect(viewModel.confirmedItems, isNull);
      expect(viewModel.confirmedTable, isNull);
      expect(viewModel.shouldClearCart, isFalse);
      expect(items, hasLength(1));
    }
  });

  test('exceção inesperada depois do dispose termina sem atualizar nem notificar', () async {
    final completer = Completer<OrderSubmission>();
    final viewModel = viewModelOf(({required table, required items}) => completer.future);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.submit(table: '12', items: items);
    expect(viewModel.status, OrderSubmissionStatus.submitting);
    expect(notifications, 1);
    await Future<void>.delayed(Duration.zero);

    viewModel.dispose();
    completer.completeError(StateError('falha interna do repository'));
    await pending;

    expect(notifications, 1);
    expect(viewModel.status, OrderSubmissionStatus.submitting);
    expect(viewModel.order, isNull);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.shouldClearCart, isFalse);
  });

  test('o repositório da fila continua só na listagem deste fake', () async {
    final repository = FakeOrderRepository(() async => OrderList.ready(const []));

    final list = await repository.list();

    expect(list.orders, isEmpty);
    expect(repository.calls, 1);
    expect(repository.createCalls, 0);
    expect(() => repository.create(table: '12', items: items), throwsA(isA<UnsupportedError>()));
  });

  const recoveredId = '00000000-0000-4000-8000-0000000000aa';
  final fixedNow = DateTime.utc(2026, 11, 8, 12, 30);

  OrderIntent pendingIntent() {
    return OrderIntent.pending(
      id: recoveredId,
      createdAt: DateTime.utc(2026, 11, 8, 12),
      table: '12',
      items: const [
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
      ],
    );
  }

  test('pending recuperado sem rejeição continua incerto depois do 401', () async {
    final store = MemoryOrderIntentStore();
    await store.save(pendingIntent());
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        return const OrderSubmission.failed(
          OrderSubmission.unauthorizedRejectionMessage,
          retainsIntent: true,
        );
      },
    );
    final viewModel = OrderSubmissionViewModel(
      orders,
      intentStore: store,
      newIntentId: () => '00000000-0000-4000-8000-0000000000bb',
      now: () => fixedNow,
    );
    addTearDown(viewModel.dispose);

    await viewModel.restore();
    await viewModel.resume(recoveredId);

    expect(orders.lastIdempotencyKey, recoveredId);
    expect(orders.createCalls, 1);
    expect(viewModel.outcomeUncertain, isTrue);
    expect(viewModel.authRejected, isFalse);
    expect(viewModel.errorMessage, contains('pode ter sido registrado'));
    expect(viewModel.canRequestSubmit, isFalse);
    final stored = await store.load();
    expect(stored?.id, recoveredId);
    expect(stored?.phase, OrderIntentPhase.uncertain);
    expect(stored?.rejection, isNull);
  });

  test('intenção expirada não reenvia o 401', () async {
    final store = MemoryOrderIntentStore();
    await store.save(pendingIntent());
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        return const OrderSubmission.failed(
          OrderSubmission.unauthorizedRejectionMessage,
          retainsIntent: true,
        );
      },
    );
    final viewModel = OrderSubmissionViewModel(
      orders,
      intentStore: store,
      newIntentId: () => '00000000-0000-4000-8000-0000000000bb',
      now: () => fixedNow.add(const Duration(hours: 23)),
    );
    addTearDown(viewModel.dispose);

    await viewModel.restore();
    await viewModel.resume(recoveredId);

    expect(orders.createCalls, 0);
    expect(viewModel.outcomeUncertain, isFalse);
    expect(viewModel.authRejected, isFalse);
    expect((await store.load())!.phase, OrderIntentPhase.blocked);
  });

  test('201 não gravado e timeout sem marca de incerto não viram recusa no 401', () async {
    Future<void> recover(int failAt, OrderSubmission first) async {
      final inner = MemoryOrderIntentStore();
      final store = _FailNthSave(inner, failAt: failAt);
      final firstModel = OrderSubmissionViewModel(
        FakeOrderRepository(
          () async => OrderList.ready(const []),
          onCreate: ({required table, required items}) async => first,
        ),
        intentStore: store,
        newIntentId: () => recoveredId,
      );
      addTearDown(firstModel.dispose);
      await firstModel.submit(table: '12', items: items);
      expect(await inner.load(), isNotNull);
      expect((await inner.load())!.phase, OrderIntentPhase.pending);
      expect((await inner.load())!.rejection, isNull);

      final orders = FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async {
          return const OrderSubmission.failed(
            OrderSubmission.unauthorizedRejectionMessage,
            retainsIntent: true,
          );
        },
      );
      final resumed = OrderSubmissionViewModel(
        orders,
        intentStore: inner,
        newIntentId: () => '00000000-0000-4000-8000-0000000000bb',
      );
      addTearDown(resumed.dispose);
      await resumed.restore();
      await resumed.resume(recoveredId);

      expect(orders.createCalls, 1);
      expect(orders.lastIdempotencyKey, recoveredId);
      expect(resumed.outcomeUncertain, isTrue);
      expect(resumed.authRejected, isFalse);
      expect(resumed.errorMessage, contains('pode ter sido registrado'));
      expect((await inner.load())!.phase, OrderIntentPhase.uncertain);
      expect((await inner.load())!.rejection, isNull);
    }

    await recover(2, OrderSubmission.created(sampleOrder(id: 'order-real')));
    await recover(
      2,
      const OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        outcomeUncertain: true,
      ),
    );
  });
}

final class _FailNthSave implements OrderIntentStore {
  _FailNthSave(this.inner, {required this.failAt});

  final MemoryOrderIntentStore inner;
  final int failAt;
  var saves = 0;

  @override
  Future<void> clear() => inner.clear();

  @override
  Future<OrderIntent?> load() => inner.load();

  @override
  Future<void> save(OrderIntent intent) async {
    saves++;
    if (saves == failAt) {
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
    }
    await inner.save(intent);
  }
}

final class _CountingLastOrderStore implements LastOrderStore {
  _CountingLastOrderStore(this._delegate);

  final LastOrderStore _delegate;
  var saveCalls = 0;

  @override
  Future<Order?> load() => _delegate.load();

  @override
  Future<void> save(Order order) async {
    saveCalls++;
    await _delegate.save(order);
  }
}
