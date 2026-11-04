import 'dart:async';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_status.dart';
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

  test('carrega a lista, sobe preparing e ordena o restante por horário', () async {
    final olderReceived = sampleOrder(
      id: 'o1',
      table: '4',
      status: OrderStatus.received,
      createdAt: DateTime.utc(2026, 10, 16, 18),
    );
    final sameTimeLaterId = sampleOrder(
      id: 'o10',
      table: '9',
      status: OrderStatus.received,
      createdAt: DateTime.utc(2026, 10, 16, 18, 5),
    );
    final sameTimeEarlierId = sampleOrder(
      id: 'o2',
      table: '7',
      status: OrderStatus.received,
      createdAt: DateTime.utc(2026, 10, 16, 18, 5),
    );
    final newerPreparing = sampleOrder(
      id: 'o3',
      table: '15',
      status: OrderStatus.preparing,
      createdAt: DateTime.utc(2026, 10, 16, 18, 10),
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

    gate.complete(
      OrderList.ready([sameTimeLaterId, olderReceived, newerPreparing, sameTimeEarlierId]),
    );
    await flushAsync();

    expect(loadings, [true, false]);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.refreshError, isNull);
    expect(viewModel.orders.map((order) => order.id), ['o3', 'o1', 'o10', 'o2']);
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
    expect(viewModel.failure, DataFailure.unavailable);
    expect(viewModel.orders, isEmpty);

    fail = false;
    await viewModel.retry();

    expect(viewModel.hasLoaded, isTrue);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
    expect(viewModel.orders, [order]);
  });

  test('a carga inicial preserva ausência sem levar o detalhe técnico à mensagem', () async {
    final repository = FakeOrderRepository(
      () async => const OrderList.unavailable(
        'Pedido não encontrado',
        failure: DataFailure.notFound,
        detail: 'Connection refused',
      ),
    );
    keep(OrdersQueueViewModel(repository, delay: ControllableDelay().call));

    viewModel.resume();
    await flushAsync();

    expect(viewModel.errorMessage, 'Pedido não encontrado');
    expect(viewModel.errorMessage, isNot(contains('Connection refused')));
    expect(viewModel.failure, DataFailure.notFound);
    expect(viewModel.refreshError, isNull);
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

  test('retoma durante a consulta e busca de novo assim que ela termina', () async {
    final gates = <Completer<OrderList>>[];
    final repository = FakeOrderRepository(() {
      final gate = Completer<OrderList>();
      gates.add(gate);
      return gate.future;
    });
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));

    viewModel.resume();
    expect(repository.calls, 1);
    expect(delay.durations, isEmpty);

    viewModel.pause();
    viewModel.resume();

    expect(repository.calls, 1);
    expect(delay.durations, isEmpty);
    expect(viewModel.orders, isEmpty);

    gates.single.complete(OrderList.ready([sampleOrder(id: 'o1', table: '4')]));
    await flushAsync();

    expect(repository.calls, 2);
    expect(delay.durations, isEmpty);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.orders.single.id, 'o1');

    gates[1].complete(OrderList.ready([sampleOrder(id: 'o2', table: '8')]));
    await flushAsync();

    expect(repository.calls, 2);
    expect(delay.durations, [OrdersQueueViewModel.defaultPollInterval]);
    expect(viewModel.orders.single.id, 'o2');
    expect(viewModel.isLoading, isFalse);
  });

  test(
    'dispose durante a retomada no meio da consulta não notifica nem consulta de novo',
    () async {
      final gates = <Completer<OrderList>>[];
      final repository = FakeOrderRepository(() {
        final gate = Completer<OrderList>();
        gates.add(gate);
        return gate.future;
      });
      final delay = ControllableDelay();
      keep(OrdersQueueViewModel(repository, delay: delay.call));
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      viewModel.resume();
      expect(notifications, 1);

      viewModel.pause();
      viewModel.resume();
      viewModel.dispose();

      gates.single.complete(OrderList.ready([sampleOrder(id: 'o1')]));
      await flushAsync();

      expect(notifications, 1);
      expect(repository.calls, 1);
      expect(delay.durations, isEmpty);
      expect(viewModel.orders, isEmpty);
      expect(viewModel.isLoading, isTrue);
    },
  );

  test('dispose da consulta pedida na retomada não notifica nem arma outro timer', () async {
    final gates = <Completer<OrderList>>[];
    final repository = FakeOrderRepository(() {
      final gate = Completer<OrderList>();
      gates.add(gate);
      return gate.future;
    });
    final delay = ControllableDelay();
    keep(OrdersQueueViewModel(repository, delay: delay.call));
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    viewModel.resume();
    viewModel.pause();
    viewModel.resume();
    gates.single.complete(OrderList.ready([sampleOrder(id: 'o1', table: '4')]));
    await flushAsync();

    expect(repository.calls, 2);
    expect(viewModel.orders.single.id, 'o1');
    final afterFirst = notifications;

    viewModel.dispose();
    gates[1].complete(OrderList.ready([sampleOrder(id: 'o2', table: '8')]));
    await flushAsync();

    expect(notifications, afterFirst);
    expect(repository.calls, 2);
    expect(delay.durations, isEmpty);
    expect(viewModel.orders.single.id, 'o1');
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

  test('oculta pedidos finished na fila ativa', () async {
    final repository = FakeOrderRepository(
      () async => OrderList.ready([
        sampleOrder(id: 'o1', status: OrderStatus.received),
        sampleOrder(id: 'o2', status: OrderStatus.finished),
      ]),
    );
    keep(OrdersQueueViewModel(repository, delay: ControllableDelay().call));

    viewModel.resume();
    await flushAsync();

    expect(viewModel.orders.map((order) => order.id), ['o1']);
  });

  test('avança status e remove o pedido ao finalizar', () async {
    final received = sampleOrder(id: 'o1', status: OrderStatus.received);
    final preparing = sampleOrder(id: 'o1', status: OrderStatus.preparing);
    final ready = sampleOrder(id: 'o1', status: OrderStatus.ready);
    final finished = sampleOrder(id: 'o1', status: OrderStatus.finished);
    final updates = <Order>[preparing, ready, finished];
    final repository = FakeOrderRepository(
      () async => OrderList.ready([received]),
      updateStatus: (id, status) async {
        expect(id, 'o1');
        return OrderUpdate.ready(updates.removeAt(0));
      },
    );
    keep(OrdersQueueViewModel(repository, delay: ControllableDelay().call));

    viewModel.resume();
    await flushAsync();

    await viewModel.advanceStatus('o1');
    expect(viewModel.orders.single.status, OrderStatus.preparing);
    expect(repository.lastUpdateStatus, OrderStatus.preparing);

    await viewModel.advanceStatus('o1');
    expect(viewModel.orders.single.status, OrderStatus.ready);

    await viewModel.advanceStatus('o1');
    expect(viewModel.orders, isEmpty);
    expect(viewModel.isEmpty, isTrue);
    expect(repository.updateCalls, 3);
  });

  test('em 409 refetch a fila e mostra status desatualizado', () async {
    final stale = sampleOrder(id: 'o1', status: OrderStatus.received);
    final current = sampleOrder(id: 'o1', status: OrderStatus.preparing);
    var lists = 0;
    final repository = FakeOrderRepository(
      () async {
        lists++;
        return OrderList.ready([lists == 1 ? stale : current]);
      },
      updateStatus: (id, status) async =>
          const OrderUpdate.unavailable('Não é permitido avançar', failure: DataFailure.conflict),
    );
    keep(OrdersQueueViewModel(repository, delay: ControllableDelay().call));

    viewModel.resume();
    await flushAsync();
    await viewModel.advanceStatus('o1');
    await flushAsync();

    expect(viewModel.actionError, OrdersQueueViewModel.staleStatusMessage);
    expect(viewModel.actionFailure, DataFailure.conflict);
    expect(viewModel.orders.single.status, OrderStatus.preparing);
    expect(repository.updateCalls, 1);
    expect(repository.calls, greaterThanOrEqualTo(2));
  });

  test('em rede mantém o status e permite nova tentativa', () async {
    final order = sampleOrder(id: 'o1', status: OrderStatus.received);
    var fail = true;
    final repository = FakeOrderRepository(
      () async => OrderList.ready([order]),
      updateStatus: (id, status) async {
        if (fail) {
          return const OrderUpdate.unavailable('Não foi possível conectar à API');
        }
        return OrderUpdate.ready(sampleOrder(id: 'o1', status: OrderStatus.preparing));
      },
    );
    keep(OrdersQueueViewModel(repository, delay: ControllableDelay().call));

    viewModel.resume();
    await flushAsync();
    await viewModel.advanceStatus('o1');

    expect(viewModel.orders.single.status, OrderStatus.received);
    expect(viewModel.actionError, 'Não foi possível conectar à API');
    expect(viewModel.isUpdating('o1'), isFalse);

    fail = false;
    await viewModel.advanceStatus('o1');

    expect(viewModel.orders.single.status, OrderStatus.preparing);
    expect(viewModel.actionError, isNull);
    expect(repository.updateCalls, 2);
  });
}
