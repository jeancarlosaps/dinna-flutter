import 'dart:async';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
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
    expect(items.single.quantity, 2);
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
    await viewModel.submit(table: '12', items: items);

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

  test('exceção inesperada sai de envio sem o detalhe interno e sem limpar', () async {
    const detalheInterno = 'falha interna do repository';
    final viewModel = viewModelOf(
      ({required table, required items}) async => throw StateError(detalheInterno),
    );
    final states = <OrderSubmissionStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    await viewModel.submit(table: '12', items: items);

    expect(states, [OrderSubmissionStatus.submitting, OrderSubmissionStatus.failed]);
    expect(viewModel.order, isNull);
    expect(viewModel.errorMessage, OrderSubmissionViewModel.unexpectedFailureMessage);
    expect(viewModel.errorMessage, isNot(contains(detalheInterno)));
    expect(viewModel.failure, DataFailure.unavailable);
    expect(viewModel.outcomeUncertain, isFalse);
    expect(viewModel.shouldClearCart, isFalse);
    expect(items, hasLength(1));
  });

  test('exceção inesperada depois do dispose termina sem atualizar nem notificar', () async {
    final completer = Completer<OrderSubmission>();
    final viewModel = viewModelOf(({required table, required items}) => completer.future);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.submit(table: '12', items: items);
    expect(viewModel.status, OrderSubmissionStatus.submitting);
    expect(notifications, 1);

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
}
