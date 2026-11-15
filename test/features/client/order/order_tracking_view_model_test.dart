import 'dart:async';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/features/client/order/order_tracking_view_model.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../restaurant/controllable_delay.dart';
import '../../restaurant/fake_order_repository.dart';
import '../../restaurant/sample_order.dart';

void main() {
  Future<void> flushAsync() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.value();
    }
  }

  FakeOrderRepository repositoryWith(Future<OrderLookup> Function(String id) onFind) {
    return FakeOrderRepository(() async => OrderList.ready(const []), onFind: onFind);
  }

  test('lê o pedido e consulta de novo a cada intervalo', () async {
    var status = OrderStatus.received;
    final repository = repositoryWith(
      (id) async => OrderLookup.ready(sampleOrder(id: id, status: status)),
    );
    final delay = ControllableDelay();
    final viewModel = OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call);
    addTearDown(viewModel.dispose);

    expect(viewModel.isLoading, isTrue);
    viewModel.resume();
    await flushAsync();

    expect(viewModel.order?.status, OrderStatus.received);
    expect(repository.lastFoundId, 'o1');
    expect(delay.durations, [OrderTrackingViewModel.defaultPollInterval]);

    status = OrderStatus.preparing;
    delay.elapse();
    await flushAsync();

    expect(repository.findCalls, 2);
    expect(viewModel.order?.status, OrderStatus.preparing);
  });

  test('para de consultar quando o pedido é finalizado', () async {
    final repository = repositoryWith(
      (id) async => OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.finished)),
    );
    final delay = ControllableDelay();
    final viewModel = OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call);
    addTearDown(viewModel.dispose);

    viewModel.resume();
    await flushAsync();

    expect(viewModel.isDone, isTrue);
    expect(delay.durations, isEmpty);
    await viewModel.retry();
    expect(repository.findCalls, 1);
  });

  test('pedido inexistente para sem tentar de novo', () async {
    final repository = repositoryWith(
      (_) async =>
          const OrderLookup.unavailable('Pedido não encontrado', failure: DataFailure.notFound),
    );
    final delay = ControllableDelay();
    final viewModel = OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call);
    addTearDown(viewModel.dispose);

    viewModel.resume();
    await flushAsync();

    expect(viewModel.notFound, isTrue);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(delay.durations, isEmpty);
  });

  test('falha sem pedido mostra o erro e a nova tentativa recupera', () async {
    var fail = true;
    final repository = repositoryWith((id) async {
      if (fail) return const OrderLookup.unavailable('Sem conexão');
      return OrderLookup.ready(sampleOrder(id: id));
    });
    final viewModel = OrderTrackingViewModel(
      repository,
      orderId: 'o1',
      delay: ControllableDelay().call,
    );
    addTearDown(viewModel.dispose);

    viewModel.resume();
    await flushAsync();
    expect(viewModel.errorMessage, 'Sem conexão');
    expect(viewModel.order, isNull);

    fail = false;
    await viewModel.retry();

    expect(viewModel.errorMessage, isNull);
    expect(viewModel.order?.status, OrderStatus.received);
  });

  test('falha numa atualização mantém o último status', () async {
    var fail = false;
    final repository = repositoryWith((id) async {
      if (fail) return const OrderLookup.unavailable('Sem conexão');
      return OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.preparing));
    });
    final delay = ControllableDelay();
    final viewModel = OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call);
    addTearDown(viewModel.dispose);

    viewModel.resume();
    await flushAsync();
    fail = true;
    delay.elapse();
    await flushAsync();

    expect(viewModel.order?.status, OrderStatus.preparing);
    expect(viewModel.refreshError, 'Sem conexão');
    expect(viewModel.errorMessage, isNull);

    fail = false;
    delay.elapse();
    await flushAsync();
    expect(viewModel.refreshError, isNull);
  });

  test('pausa segura a consulta e retomar consulta na hora', () async {
    final repository = repositoryWith((id) async => OrderLookup.ready(sampleOrder(id: id)));
    final delay = ControllableDelay();
    final viewModel = OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call);
    addTearDown(viewModel.dispose);

    viewModel.resume();
    await flushAsync();
    viewModel.pause();
    delay.elapse();
    await flushAsync();
    expect(repository.findCalls, 1);

    viewModel.resume();
    await flushAsync();
    expect(repository.findCalls, 2);
  });

  test('resposta depois do dispose não notifica', () async {
    final repository = repositoryWith((id) async => OrderLookup.ready(sampleOrder(id: id)));
    final viewModel = OrderTrackingViewModel(
      repository,
      orderId: 'o1',
      delay: ControllableDelay().call,
    );
    var notified = 0;
    viewModel.addListener(() => notified++);

    viewModel.resume();
    final before = notified;
    viewModel.dispose();
    await flushAsync();

    expect(notified, before);
  });

  test('erro inesperado do repository vira mensagem de falha', () async {
    final repository = repositoryWith((_) async => throw StateError('falha'));
    final viewModel = OrderTrackingViewModel(
      repository,
      orderId: 'o1',
      delay: ControllableDelay().call,
    );
    addTearDown(viewModel.dispose);

    viewModel.resume();
    await flushAsync();

    expect(viewModel.errorMessage, OrderTrackingViewModel.unexpectedFailureMessage);
  });

  test('retomar durante uma consulta em voo consulta de novo assim que ela termina', () async {
    final pending = Completer<OrderLookup>();
    var calls = 0;
    final repository = repositoryWith((id) {
      calls++;
      if (calls == 1) return pending.future;
      return Future.value(OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.ready)));
    });
    final delay = ControllableDelay();
    final viewModel = OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call);
    addTearDown(viewModel.dispose);

    viewModel.resume();
    await flushAsync();
    viewModel.pause();
    viewModel.resume();
    pending.complete(OrderLookup.ready(sampleOrder(id: 'o1')));
    await flushAsync();

    expect(repository.findCalls, 2);
    expect(viewModel.order?.status, OrderStatus.ready);
  });

  test('pausar durante a consulta em voo não antecipa a próxima', () async {
    final pending = Completer<OrderLookup>();
    final repository = repositoryWith((_) => pending.future);
    final delay = ControllableDelay();
    final viewModel = OrderTrackingViewModel(repository, orderId: 'o1', delay: delay.call);
    addTearDown(viewModel.dispose);

    viewModel.resume();
    await flushAsync();
    viewModel.pause();
    pending.complete(OrderLookup.ready(sampleOrder(id: 'o1')));
    await flushAsync();

    expect(repository.findCalls, 1);
    expect(delay.durations, [OrderTrackingViewModel.defaultPollInterval]);
  });

  test(
    'retomar antes do intervalo cancela o Timer anterior e o dispose não deixa Timer ativo',
    () async {
      // Intercepta só os Timers do intervalo, sem esperar os cinco segundos.
      final timers = <Timer>[];
      final repository = repositoryWith(
        (id) async => OrderLookup.ready(sampleOrder(id: id, status: OrderStatus.received)),
      );
      final viewModel = runZoned(
        () => OrderTrackingViewModel(repository, orderId: 'o1')..resume(),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            if (duration == OrderTrackingViewModel.defaultPollInterval) timers.add(timer);
            return timer;
          },
        ),
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) viewModel.dispose();
      });

      await flushAsync();
      expect(repository.findCalls, 1);
      expect(timers, hasLength(1));
      expect(timers.single.isActive, isTrue);

      viewModel.pause();
      viewModel.resume();
      await flushAsync();

      expect(timers.first.isActive, isFalse);
      expect(repository.findCalls, 2);
      expect(viewModel.order?.status, OrderStatus.received);
      expect(timers, hasLength(2));
      expect(timers.last.isActive, isTrue);

      viewModel.dispose();
      disposed = true;
      await flushAsync();

      expect(timers.where((timer) => timer.isActive), isEmpty);
      expect(repository.findCalls, 2);
    },
  );
}
