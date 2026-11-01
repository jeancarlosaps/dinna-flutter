import 'dart:async';
import 'dart:io';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/features/client/order/order_intent.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../restaurant/fake_order_repository.dart';
import '../../restaurant/sample_order.dart';

void main() {
  final original = [
    CartItem(productId: 'p1', quantity: 2, note: 'sem cebola'),
    CartItem(productId: 'p2', quantity: 1, note: null),
    CartItem(productId: 'p3', quantity: 1, note: ''),
  ];

  String idAt(int sequence) => '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}';

  OrderSubmissionViewModel open({
    required FakeOrderRepository repository,
    required OrderIntentStore store,
    required List<String> ids,
    required DateTime Function() now,
  }) {
    return OrderSubmissionViewModel(
      repository,
      intentStore: store,
      now: now,
      newIntentId: () {
        final id = idAt(ids.length + 1);
        ids.add(id);
        return id;
      },
    );
  }

  test('o primeiro envio grava a chave antes do POST e o retry repete os dois', () async {
    final ids = <String>[];
    final bodies = <Map<String, Object?>?>[];
    final keys = <String?>[];
    final now = DateTime.utc(2026, 11, 1, 12);
    var fail = true;
    var savedBeforePost = false;
    final store = MemoryOrderIntentStore();
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        savedBeforePost = (await store.load())?.id == ids.single;
        if (fail) {
          return const OrderSubmission.failed(
            OrderSubmission.uncertainOutcomeMessage,
            failure: DataFailure.uncertain,
            outcomeUncertain: true,
          );
        }
        return OrderSubmission.created(sampleOrder(id: 'o1'));
      },
    );
    final viewModel = open(repository: repository, store: store, ids: ids, now: () => now);

    final cart = [...original];
    await viewModel.submit(table: '12', items: cart);
    keys.add(repository.lastIdempotencyKey);
    bodies.add(repository.lastBody);
    cart[0] = CartItem(productId: 'p1', quantity: 9, note: 'com cebola');
    cart.add(CartItem(productId: 'p4', quantity: 1, note: null));

    expect(savedBeforePost, isTrue);
    expect(ids, [idAt(1)]);
    expect(viewModel.outcomeUncertain, isTrue);
    expect(viewModel.canRequestSubmit, isFalse);
    expect(viewModel.canResumeSameIntent, isTrue);
    expect(viewModel.shouldClearCart, isFalse);

    fail = false;
    await viewModel.submit(table: '99', items: cart, confirmedResume: true);

    expect(repository.createCalls, 2);
    expect(ids, [idAt(1)]);
    expect(repository.lastIdempotencyKey, keys.single);
    expect(repository.lastBody, bodies.single);
    expect(repository.lastBody!['table'], '12');
    expect(repository.lastBody!['items'], [
      {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
      {'productId': 'p2', 'quantity': 1},
      {'productId': 'p3', 'quantity': 1, 'note': ''},
    ]);
    expect(viewModel.status, OrderSubmissionStatus.succeeded);
    expect(viewModel.order!.id, 'o1');
    expect(viewModel.shouldClearCart, isTrue);
    expect(cart, hasLength(4));
  });

  test('dois submits no mesmo instante criam uma intenção só', () async {
    final ids = <String>[];
    final gate = Completer<OrderSubmission>();
    final now = DateTime.utc(2026, 11, 1, 12);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) => gate.future,
    );
    final viewModel = open(
      repository: repository,
      store: MemoryOrderIntentStore(),
      ids: ids,
      now: () => now,
    );

    final first = viewModel.submit(table: '12', items: original);
    final second = viewModel.submit(table: '12', items: original);
    await Future<void>.delayed(Duration.zero);

    expect(repository.createCalls, 1);
    expect(ids, [idAt(1)]);
    expect(viewModel.isSubmitting, isTrue);

    gate.complete(OrderSubmission.created(sampleOrder(id: 'o1')));
    await first;
    await second;

    expect(repository.createCalls, 1);
    expect(viewModel.canRequestSubmit, isFalse);
  });

  test('reinício recupera a chave e não envia sozinho', () async {
    final ids = <String>[];
    final now = DateTime.utc(2026, 11, 1, 12);
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileOrderIntentStore(File('${directory.path}/order-intent.json'));
    final firstRepository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async => const OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        outcomeUncertain: true,
      ),
    );
    final first = open(repository: firstRepository, store: store, ids: ids, now: () => now);
    await first.submit(table: '12', items: original);

    final secondRepository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o9')),
    );
    final second = open(repository: secondRepository, store: store, ids: ids, now: () => now);
    await second.restore();

    expect(secondRepository.createCalls, 0);
    expect(second.outcomeUncertain, isTrue);
    expect(second.intentId, idAt(1));
    expect(second.canRequestSubmit, isFalse);
    expect(second.canResumeSameIntent, isTrue);

    await second.submit(
      table: '12',
      items: [CartItem(productId: 'p9', quantity: 4, note: null)],
    );
    expect(secondRepository.createCalls, 0);

    await second.submit(
      table: '12',
      items: [CartItem(productId: 'p9', quantity: 4, note: null)],
      confirmedResume: true,
    );

    expect(secondRepository.createCalls, 1);
    expect(secondRepository.lastIdempotencyKey, idAt(1));
    expect(secondRepository.lastBody!['items'], [
      {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
      {'productId': 'p2', 'quantity': 1},
      {'productId': 'p3', 'quantity': 1, 'note': ''},
    ]);
    expect(ids, [idAt(1)]);
  });

  test(
    'falha confirmada encerra a intenção e a próxima usa outro UUID e o carrinho atual',
    () async {
      final ids = <String>[];
      final now = DateTime.utc(2026, 11, 1, 12);
      final store = MemoryOrderIntentStore();
      var reject = true;
      final repository = FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async {
          if (reject) {
            return const OrderSubmission.failed(
              'Produto indisponível',
              failure: DataFailure.notFound,
            );
          }
          return OrderSubmission.created(sampleOrder(id: 'o2'));
        },
      );
      final viewModel = open(repository: repository, store: store, ids: ids, now: () => now);

      await viewModel.submit(table: '12', items: original);
      expect(viewModel.isDefiniteFailure, isTrue);
      expect(viewModel.canRequestSubmit, isTrue);
      expect(await store.load(), isNull);

      reject = false;
      final edited = [CartItem(productId: 'p1', quantity: 5, note: 'sem cebola')];
      await viewModel.submit(table: '12', items: edited);

      expect(ids, [idAt(1), idAt(2)]);
      expect(repository.lastIdempotencyKey, idAt(2));
      expect(repository.lastBody!['items'], [
        {'productId': 'p1', 'quantity': 5, 'note': 'sem cebola'},
      ]);
      expect(viewModel.shouldClearCart, isTrue);
      expect(edited.single.quantity, 5);
    },
  );

  test('409 e chave órfã não disparam outro POST', () async {
    final ids = <String>[];
    final now = DateTime.utc(2026, 11, 1, 12);
    for (final blocked in [
      const OrderSubmission.blocked(
        OrderSubmission.idempotencyConflictMessage,
        failure: DataFailure.conflict,
      ),
      const OrderSubmission.blocked(
        OrderSubmission.idempotencyInvalidMessage,
        failure: DataFailure.unavailable,
      ),
    ]) {
      final repository = FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async => blocked,
      );
      final viewModel = open(
        repository: repository,
        store: MemoryOrderIntentStore(),
        ids: ids,
        now: () => now,
      );

      await viewModel.submit(table: '12', items: original);
      await viewModel.submit(
        table: '12',
        items: [CartItem(productId: 'p9', quantity: 1, note: null)],
      );

      expect(repository.createCalls, 1);
      expect(viewModel.resendBlocked, isTrue);
      expect(viewModel.canRequestSubmit, isFalse);
      expect(viewModel.canResumeSameIntent, isFalse);
      expect(viewModel.shouldClearCart, isFalse);
    }
  });

  test('chave com 23 horas ou relógio no passado não é reenviada', () async {
    final ids = <String>[];
    var now = DateTime.utc(2026, 11, 1, 12);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async => const OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        outcomeUncertain: true,
      ),
    );
    final viewModel = open(
      repository: repository,
      store: MemoryOrderIntentStore(),
      ids: ids,
      now: () => now,
    );

    await viewModel.submit(table: '12', items: original);
    now = DateTime.utc(2026, 11, 2, 11);
    await viewModel.submit(table: '12', items: original);

    expect(repository.createCalls, 1);
    expect(viewModel.resendBlocked, isTrue);
    expect(viewModel.errorMessage, OrderSubmissionViewModel.expiredIntentMessage);
    expect(viewModel.errorMessage, contains('não significa'));
    expect(viewModel.canResumeSameIntent, isFalse);
    expect(ids, [idAt(1)]);
  });

  test('relógio que volta deixa a intenção no futuro e bloqueia o reenvio', () async {
    final ids = <String>[];
    var now = DateTime.utc(2026, 11, 1, 12);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async => const OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        outcomeUncertain: true,
      ),
    );
    final viewModel = open(
      repository: repository,
      store: MemoryOrderIntentStore(),
      ids: ids,
      now: () => now,
    );

    await viewModel.submit(table: '12', items: original);
    now = DateTime.utc(2026, 11, 1, 11, 59);
    await viewModel.submit(table: '12', items: original);

    expect(repository.createCalls, 1);
    expect(viewModel.resendBlocked, isTrue);
    expect(viewModel.canRequestSubmit, isFalse);
  });

  test('falha ao gravar impede o POST e a corrupção não libera outro', () async {
    final ids = <String>[];
    final now = DateTime.utc(2026, 11, 1, 12);
    final missing = MemoryOrderIntentStore()..failNextSave();
    final missingRepository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final missingViewModel = open(
      repository: missingRepository,
      store: missing,
      ids: ids,
      now: () => now,
    );

    await missingViewModel.submit(table: '12', items: original);

    expect(missingRepository.createCalls, 0);
    expect(missingViewModel.isDefiniteFailure, isTrue);
    expect(missingViewModel.errorMessage, OrderSubmissionViewModel.persistFailureMessage);
    expect(missingViewModel.canRequestSubmit, isTrue);

    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/order-intent.json');
    await file.writeAsString('{', flush: true);
    final corruptRepository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final corruptViewModel = open(
      repository: corruptRepository,
      store: FileOrderIntentStore(file),
      ids: ids,
      now: () => now,
    );

    await corruptViewModel.submit(table: '12', items: original);
    await corruptViewModel.submit(table: '12', items: original);

    expect(corruptRepository.createCalls, 0);
    expect(corruptViewModel.resendBlocked, isTrue);
    expect(corruptViewModel.canRequestSubmit, isFalse);
    expect(corruptViewModel.errorMessage, OrderSubmissionViewModel.unreadableIntentMessage);
    expect(await file.readAsString(), '{');
  });

  test('gravação que chega a disco e depois falha não troca a chave', () async {
    final ids = <String>[];
    final now = DateTime.utc(2026, 11, 1, 12);
    final inner = MemoryOrderIntentStore();
    final store = _WriteThenFail(inner);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final viewModel = open(repository: repository, store: store, ids: ids, now: () => now);

    await viewModel.submit(table: '12', items: original);

    expect(repository.createCalls, 0);
    expect(viewModel.outcomeUncertain, isTrue);
    expect((await inner.load())!.id, idAt(1));

    await viewModel.submit(
      table: '8',
      items: [CartItem(productId: 'p9', quantity: 3, note: null)],
      confirmedResume: true,
    );

    expect(repository.createCalls, 1);
    expect(repository.lastIdempotencyKey, idAt(1));
    expect(ids, [idAt(1)]);
  });

  test('edição da lista durante a leitura não entra no body da chave', () async {
    final live = <CartItem>[CartItem(productId: 'p1', quantity: 2, note: 'sem cebola')];
    final items = List<CartItem>.unmodifiable(live);
    final ids = <String>[];
    final now = DateTime.utc(2026, 11, 1, 12);
    final store = _GateStore(MemoryOrderIntentStore());
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final viewModel = open(repository: repository, store: store, ids: ids, now: () => now);
    viewModel.addListener(() {
      if (!viewModel.isSubmitting) return;
      live
        ..clear()
        ..add(CartItem(productId: 'p9', quantity: 4, note: 'mudou'));
    });

    final pending = viewModel.submit(table: '12', items: items);
    store.release();
    await pending;

    expect(repository.createCalls, 1);
    expect(repository.lastIdempotencyKey, idAt(1));
    expect(repository.lastBody!['items'], [
      {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
    ]);
    expect((await store.load())!.cartItems.single.note, 'sem cebola');
    expect(live.single.productId, 'p9');
  });

  test('note longa na intenção recuperada bloqueia o POST e preserva o arquivo', () async {
    final ids = <String>[];
    final now = DateTime.utc(2026, 11, 1, 12);
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/order-intent.json');
    final note = 'n' * 201;
    final raw =
        '{"id":"${idAt(1)}","createdAt":"2026-11-01T12:00:00Z","phase":"succeeded","table":"12","items":[{"productId":"p1","quantity":2,"note":"$note"}],"order":{"id":"o1","table":"12","status":"received","items":[{"productId":"p1","quantity":2}],"totalCents":1000,"createdAt":"2026-10-16T18:00:00Z"}}';
    await file.writeAsString(raw, flush: true);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o2')),
    );
    final viewModel = open(
      repository: repository,
      store: FileOrderIntentStore(file),
      ids: ids,
      now: () => now,
    );

    await viewModel.restore();
    await viewModel.submit(table: '12', items: original);

    expect(repository.createCalls, 0);
    expect(ids, isEmpty);
    expect(viewModel.resendBlocked, isTrue);
    expect(viewModel.canRequestSubmit, isFalse);
    expect(viewModel.errorMessage, OrderSubmissionViewModel.unreadableIntentMessage);
    expect(await file.readAsString(), raw);
  });

  test('sucesso confirmado não reenvia no reinício e o ciclo seguinte usa outra chave', () async {
    final ids = <String>[];
    final store = MemoryOrderIntentStore();
    final now = DateTime.utc(2026, 11, 1, 12);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final first = open(repository: repository, store: store, ids: ids, now: () => now);

    await first.submit(table: '12', items: original);

    expect(first.status, OrderSubmissionStatus.succeeded);
    expect(first.canBeginAnotherOrder, isTrue);
    expect(first.canRequestSubmit, isFalse);
    await first.submit(
      table: '99',
      items: [CartItem(productId: 'p9', quantity: 1, note: null)],
    );
    expect(repository.createCalls, 1);
    expect(ids, [idAt(1)]);

    final restarted = open(repository: repository, store: store, ids: ids, now: () => now);
    await restarted.restore();
    await restarted.submit(table: '12', items: original);

    expect(repository.createCalls, 1);
    expect(restarted.status, OrderSubmissionStatus.succeeded);
    expect(restarted.order!.id, 'o1');
    expect(restarted.canBeginAnotherOrder, isTrue);
    expect(restarted.canRequestSubmit, isFalse);
    expect((await store.load())!.id, idAt(1));

    await restarted.beginAnotherOrder();

    expect(await store.load(), isNull);
    expect(restarted.status, OrderSubmissionStatus.idle);
    expect(restarted.order, isNull);
    expect(restarted.canRequestSubmit, isTrue);
    expect(repository.createCalls, 1);

    await restarted.submit(
      table: '7',
      items: [CartItem(productId: 'p1', quantity: 4, note: 'sem cebola')],
    );

    expect(repository.createCalls, 2);
    expect(ids, [idAt(1), idAt(2)]);
    expect(repository.lastIdempotencyKey, idAt(2));
    expect(repository.lastBody!['table'], '7');
    expect(repository.lastBody!['items'], [
      {'productId': 'p1', 'quantity': 4, 'note': 'sem cebola'},
    ]);
  });

  test('intenção incerta não é descartada ao pedir outro ciclo', () async {
    final ids = <String>[];
    final store = MemoryOrderIntentStore();
    final now = DateTime.utc(2026, 11, 1, 12);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        return const OrderSubmission.failed(
          OrderSubmission.uncertainOutcomeMessage,
          failure: DataFailure.uncertain,
          outcomeUncertain: true,
        );
      },
    );
    final viewModel = open(repository: repository, store: store, ids: ids, now: () => now);

    await viewModel.submit(table: '12', items: original);
    expect(viewModel.canBeginAnotherOrder, isFalse);

    await viewModel.beginAnotherOrder();

    expect((await store.load())!.id, idAt(1));
    expect(viewModel.outcomeUncertain, isTrue);
    await viewModel.submit(
      table: '12',
      items: [CartItem(productId: 'p9', quantity: 3, note: null)],
    );
    expect(repository.createCalls, 1);
    expect(ids, [idAt(1)]);
  });

  test('falha ao apagar o sucesso confirmado preserva a confirmação e bloqueia o POST', () async {
    final ids = <String>[];
    final store = MemoryOrderIntentStore();
    final now = DateTime.utc(2026, 11, 1, 12);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final viewModel = open(repository: repository, store: store, ids: ids, now: () => now);

    await viewModel.submit(table: '12', items: original);
    store.failNextSave();
    await viewModel.beginAnotherOrder();

    expect(viewModel.status, OrderSubmissionStatus.succeeded);
    expect(viewModel.order!.id, 'o1');
    expect(viewModel.canRequestSubmit, isFalse);
    expect(viewModel.canBeginAnotherOrder, isFalse);
    expect(viewModel.errorMessage, OrderSubmissionViewModel.unreadableIntentMessage);
    expect((await store.load())!.phase, OrderIntentPhase.succeeded);

    await viewModel.submit(table: '7', items: original);

    expect(repository.createCalls, 1);
    expect(ids, [idAt(1)]);
  });

  test('store indisponível não envia', () async {
    final ids = <String>[];
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final viewModel = open(
      repository: repository,
      store: const UnavailableOrderIntentStore(),
      ids: ids,
      now: () => DateTime.utc(2026, 11, 1, 12),
    );

    await viewModel.restore();
    await viewModel.submit(table: '12', items: original);

    expect(repository.createCalls, 0);
    expect(ids, isEmpty);
    expect(viewModel.canRequestSubmit, isFalse);
    expect(viewModel.errorMessage, OrderSubmissionViewModel.unreadableIntentMessage);
  });

  test('confirmação tardia publica a expiração e não envia', () async {
    final ids = <String>[];
    var now = DateTime.utc(2026, 11, 1, 12);
    final store = MemoryOrderIntentStore();
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        return const OrderSubmission.failed(
          OrderSubmission.uncertainOutcomeMessage,
          failure: DataFailure.uncertain,
          outcomeUncertain: true,
        );
      },
    );
    final viewModel = open(repository: repository, store: store, ids: ids, now: () => now);

    await viewModel.submit(table: '12', items: original);
    now = now.add(const Duration(hours: 23));
    await viewModel.submit(
      table: '99',
      items: [CartItem(productId: 'p9', quantity: 8, note: 'outro')],
      confirmedResume: true,
    );

    expect(repository.createCalls, 1);
    expect(ids, [idAt(1)]);
    expect(viewModel.resendBlocked, isTrue);
    expect(viewModel.canRequestSubmit, isFalse);
    expect(viewModel.errorMessage, OrderSubmissionViewModel.expiredIntentMessage);
    expect((await store.load())!.block, OrderIntentBlock.expired);

    now = DateTime.utc(2026, 11, 1, 12, 30);
    final backward = open(
      repository: repository,
      store: MemoryOrderIntentStore(),
      ids: ids,
      now: () => now,
    );
    await backward.submit(table: '12', items: original);
    now = now.subtract(const Duration(minutes: 1));
    await backward.submit(table: '12', items: original, confirmedResume: true);

    expect(repository.createCalls, 2);
    expect(backward.errorMessage, OrderSubmissionViewModel.expiredIntentMessage);
    expect(backward.canRequestSubmit, isFalse);
  });

  test('diretório inacessível não vira intenção nova', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() async {
      await Process.run('chmod', ['700', directory.path]);
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/order-intent.json');
    final store = FileOrderIntentStore(file);
    final ids = <String>[];
    final now = DateTime.utc(2026, 11, 1, 12);
    await store.save(
      OrderIntent.pending(
        id: idAt(9),
        createdAt: now,
        table: '12',
        items: OrderRequest.itemMaps(original),
      ),
    );
    final before = await file.readAsString();
    expect((await Process.run('chmod', ['000', directory.path])).exitCode, 0);
    final repository = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'o1')),
    );
    final viewModel = open(repository: repository, store: store, ids: ids, now: () => now);

    await viewModel.restore();
    await viewModel.submit(table: '12', items: original);

    expect(repository.createCalls, 0);
    expect(ids, isEmpty);
    expect(viewModel.canRequestSubmit, isFalse);
    await Process.run('chmod', ['700', directory.path]);
    expect(await file.readAsString(), before);
  });
}

final class _GateStore implements OrderIntentStore {
  _GateStore(this._inner);

  final OrderIntentStore _inner;
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> clear() => _inner.clear();

  @override
  Future<OrderIntent?> load() async {
    await _gate.future;
    return _inner.load();
  }

  @override
  Future<void> save(OrderIntent intent) => _inner.save(intent);
}

final class _WriteThenFail implements OrderIntentStore {
  _WriteThenFail(this._inner);

  final MemoryOrderIntentStore _inner;
  var _armed = true;

  @override
  Future<void> clear() => _inner.clear();

  @override
  Future<OrderIntent?> load() => _inner.load();

  @override
  Future<void> save(OrderIntent intent) async {
    await _inner.save(intent);
    if (_armed) {
      _armed = false;
      throw const OrderIntentStoreException(OrderIntentStoreProblem.unwritable);
    }
  }
}
