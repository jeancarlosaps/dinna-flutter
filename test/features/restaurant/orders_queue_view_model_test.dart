import 'dart:async';

import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:dinna/features/restaurant/orders_queue_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controllable_delay.dart';
import 'fake_order_repository.dart';
import 'sample_order.dart';

void main() {
  late OrdersQueueViewModel viewModel;

  void keep(OrdersQueueViewModel created) {
    viewModel = created;
    addTearDown(viewModel.dispose);
  }

  Future<void> flushAsync() async {
    await Future<void>.value();
    await Future<void>.value();
  }

  test('carrega a lista, ordena por horário e não ocupa a tela na atualização', () async {
    final older = sampleOrder(id: 'o1', table: '4', createdAt: DateTime.utc(2026, 10, 16, 18));
    final sameTimeLaterId = sampleOrder(
      id: 'o10',
      table: '9',
      createdAt: DateTime.utc(2026, 10, 16, 18, 5),
    );
    final sameTimeEarlierId = sampleOrder(
      id: 'o2',
      table: '7',
      createdAt: DateTime.utc(2026, 10, 16, 18, 5),
    );
    final gate = Completer<OrderList>();
    final repository = FakeOrderRepository(() => gate.future);
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));
    final loadings = <bool>[];
    viewModel.addListener(() => loadings.add(viewModel.isLoading));

    viewModel.resume();

    expect(viewModel.isLoading, isTrue);
    expect(viewModel.orders, isEmpty);
    expect(viewModel.isEmpty, isFalse);
    expect(repository.calls, 1);
    expect(delay.durations, isEmpty);

    gate.complete(OrderList.ready([sameTimeLaterId, older, sameTimeEarlierId]));
    await flushAsync();

    expect(loadings, [true, false]);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.refreshError, isNull);
    expect(viewModel.orders.map((order) => order.id), ['o1', 'o10', 'o2']);
    expect(delay.durations, [OrdersQueueViewModel.defaultPollInterval]);
  });

  test('trata lista vazia como fila sem pedidos', () async {
    final repository = FakeOrderRepository(() async => OrderList.ready(const []));
    keep(OrdersQueueViewModel(repository, delay: ControllableDelay().call));

    viewModel.resume();
    await flushAsync();

    expect(viewModel.hasLoaded, isTrue);
    expect(viewModel.isEmpty, isTrue);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.orders, isEmpty);
  });

  test('carga inicial falha e o retry mostra a fila', () async {
    final order = sampleOrder(id: 'o1');
    var fail = true;
    final repository = FakeOrderRepository(() async {
      if (fail) return const OrderList.unavailable('Não foi possível conectar à API');
      return OrderList.ready([order]);
    });
    keep(OrdersQueueViewModel(repository, delay: ControllableDelay().call));

    viewModel.resume();
    await flushAsync();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.hasLoaded, isFalse);
    expect(viewModel.isEmpty, isFalse);
    expect(viewModel.errorMessage, 'Não foi possível conectar à API');
    expect(viewModel.orders, isEmpty);

    fail = false;
    await viewModel.retry();

    expect(viewModel.hasLoaded, isTrue);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.orders, [order]);
  });

  test('exceção inesperada vira erro de tela sem o detalhe interno', () async {
    const detalheInterno = 'falha interna do repository';
    final repository = FakeOrderRepository(() async => throw StateError(detalheInterno));
    keep(OrdersQueueViewModel(repository, delay: ControllableDelay().call));

    viewModel.resume();
    await flushAsync();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.hasLoaded, isFalse);
    expect(viewModel.errorMessage, OrdersQueueViewModel.unexpectedFailureMessage);
    expect(viewModel.errorMessage, isNot(contains(detalheInterno)));
  });

  test('não dispara outra consulta enquanto a anterior está em andamento', () async {
    final gates = <Completer<OrderList>>[];
    final repository = FakeOrderRepository(() {
      final gate = Completer<OrderList>();
      gates.add(gate);
      return gate.future;
    });
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));

    viewModel.resume();
    expect(gates, hasLength(1));
    expect(delay.durations, isEmpty);

    final ignored = viewModel.retry();
    expect(gates, hasLength(1));

    gates.single.complete(OrderList.ready([sampleOrder(id: 'o1')]));
    await flushAsync();
    await ignored;

    expect(gates, hasLength(1));
    expect(delay.durations, [OrdersQueueViewModel.defaultPollInterval]);
    expect(viewModel.isLoading, isFalse);

    delay.elapse();
    await flushAsync();

    expect(gates, hasLength(2));
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.orders.single.id, 'o1');
    expect(delay.durations, hasLength(1));
  });

  test('atualização com os mesmos pedidos não notifica de novo', () async {
    final order = sampleOrder(id: 'o1', table: '4');
    final gates = <Completer<OrderList>>[];
    final repository = FakeOrderRepository(() {
      final gate = Completer<OrderList>();
      gates.add(gate);
      return gate.future;
    });
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));

    viewModel.resume();
    gates.single.complete(OrderList.ready([order]));
    await flushAsync();

    var notifications = 0;
    viewModel.addListener(() => notifications++);
    delay.elapse();
    await flushAsync();
    gates[1].complete(
      OrderList.ready([sampleOrder(id: order.id, table: order.table, createdAt: order.createdAt)]),
    );
    await flushAsync();

    expect(notifications, 0);
    expect(viewModel.orders, [order]);
    expect(viewModel.refreshError, isNull);
  });

  test('preserva a lista quando a atualização falha e limpa o aviso ao recuperar', () async {
    final order = sampleOrder(id: 'o1', table: '4');
    final gates = <Completer<OrderList>>[];
    final repository = FakeOrderRepository(() {
      final gate = Completer<OrderList>();
      gates.add(gate);
      return gate.future;
    });
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));

    viewModel.resume();
    gates.single.complete(OrderList.ready([order]));
    await flushAsync();

    delay.elapse();
    await flushAsync();
    expect(viewModel.isLoading, isFalse);
    expect(gates, hasLength(2));

    gates[1].complete(const OrderList.unavailable('sem rede'));
    await flushAsync();

    expect(viewModel.orders, [order]);
    expect(viewModel.hasLoaded, isTrue);
    expect(viewModel.isEmpty, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.refreshError, 'sem rede');
    expect(viewModel.isLoading, isFalse);

    delay.elapse();
    await flushAsync();
    gates[2].complete(OrderList.ready([sampleOrder(id: 'o2', table: '8')]));
    await flushAsync();

    expect(viewModel.refreshError, isNull);
    expect(viewModel.orders.single.id, 'o2');
    expect(viewModel.isLoading, isFalse);
  });

  test('pausa a rotina e atualiza na hora ao retomar', () async {
    final gates = <Completer<OrderList>>[];
    final repository = FakeOrderRepository(() {
      final gate = Completer<OrderList>();
      gates.add(gate);
      return gate.future;
    });
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));

    viewModel.resume();
    viewModel.resume();
    gates.single.complete(OrderList.ready([sampleOrder(id: 'o1')]));
    await flushAsync();
    expect(gates, hasLength(1));

    viewModel.pause();
    delay.elapse();
    await flushAsync();

    expect(gates, hasLength(1));

    viewModel.resume();
    await flushAsync();

    expect(gates, hasLength(2));
  });

  test('descarta a resposta e não notifica depois do dispose', () async {
    final gate = Completer<OrderList>();
    final repository = FakeOrderRepository(() => gate.future);
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    viewModel.resume();
    expect(notifications, 1);
    expect(viewModel.isLoading, isTrue);

    viewModel.dispose();
    gate.complete(OrderList.ready([sampleOrder(id: 'o1')]));
    await flushAsync();

    expect(notifications, 1);
    expect(viewModel.orders, isEmpty);
    expect(viewModel.isLoading, isTrue);
    expect(repository.calls, 1);
    expect(delay.durations, isEmpty);
  });

  test('encerra a rotina no meio da espera e não consulta de novo', () async {
    final repository = FakeOrderRepository(() async => OrderList.ready([sampleOrder(id: 'o1')]));
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));
    var notifications = 0;

    viewModel.resume();
    await flushAsync();
    viewModel.addListener(() => notifications++);
    expect(delay.durations, hasLength(1));

    viewModel.dispose();
    delay.elapse();
    await flushAsync();

    expect(repository.calls, 1);
    expect(notifications, 0);
    expect(viewModel.orders.single.id, 'o1');
  });
}
