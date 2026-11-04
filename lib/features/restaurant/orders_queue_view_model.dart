import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/domain/data_failure.dart';
import '../../core/domain/order.dart';
import '../../core/domain/order_status.dart';
import 'order_repository.dart';

/// Fila do restaurante: ViewModel → [OrderRepository]. Não conhece HTTP.
///
/// O polling é uma única rotina por instância. [defaultPollInterval] é o
/// intervalo entre consultas bem iniciadas. Enquanto uma consulta está em
/// voo, outra não começa. [pause] segura a próxima. [resume] busca na hora;
/// se a consulta atual ainda não terminou, a seguinte começa assim que ela
/// acabar, sem esperar o intervalo. Depois do [dispose], a resposta pendente
/// não altera estado nem notifica.
///
/// A ordenação é local: `ready` sobe primeiro, depois `preparing`; dentro do
/// mesmo grupo, `createdAt` crescente e, no empate, `id` lexicográfico.
/// Pedidos `finished` não entram na fila ativa. Nomes vêm em `OrderItem.name`.
class OrdersQueueViewModel extends ChangeNotifier {
  OrdersQueueViewModel(
    this._repository, {
    this.pollInterval = defaultPollInterval,
    Future<void> Function(Duration duration)? delay,
  }) : _delay = delay ?? _wait;

  final OrderRepository _repository;
  final Duration pollInterval;
  final Future<void> Function(Duration duration) _delay;

  /// Intervalo entre atualizações automáticas da fila.
  static const defaultPollInterval = Duration(seconds: 10);

  /// Mensagem de tela quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedFailureMessage = 'Não foi possível carregar a fila';

  /// Mensagem quando o avanço falha sem texto utilizável.
  static const unexpectedAdvanceMessage = 'Não foi possível atualizar o status';

  /// Conflito de transição (ex.: outro device já avançou).
  static const staleStatusMessage = 'Status desatualizado. Atualizamos a fila.';

  static Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

  List<Order> _orders = const [];
  bool _hasLoaded = false;
  bool _loading = false;
  String? _errorMessage;
  String? _refreshError;
  String? _actionError;
  DataFailure? _failure;
  DataFailure? _actionFailure;
  final Set<String> _updatingIds = {};
  bool _active = false;
  bool _started = false;
  bool _disposed = false;
  bool _inFlight = false;
  bool _refreshSoon = false;
  Completer<void>? _signal;

  /// Pedidos ativos já ordenados. Vazio antes da primeira resposta com sucesso.
  List<Order> get orders => _orders;

  /// Carregamento que ocupa a tela. Atualização com dados na tela não liga isto.
  bool get isLoading => _loading;

  /// Houve ao menos uma lista válida. Erro de atualização não apaga este fato.
  bool get hasLoaded => _hasLoaded;

  /// Erro da carga inicial ou do retry, quando ainda não há lista para mostrar.
  String? get errorMessage => _errorMessage;

  /// Falha de uma atualização depois que a lista já existe. A lista permanece.
  String? get refreshError => _refreshError;

  /// Falha do último avanço de status. A lista permanece no status anterior.
  String? get actionError => _actionError;

  /// Classificação da falha atual, inicial ou de atualização. Nula com a lista válida.
  DataFailure? get failure => _failure;

  /// Classificação da falha do avanço. Nula quando o avanço não falhou.
  DataFailure? get actionFailure => _actionFailure;

  /// Lista válida e sem pedidos. Erro inicial não é fila vazia.
  bool get isEmpty => _hasLoaded && _orders.isEmpty && _errorMessage == null;

  /// `true` enquanto o PATCH deste pedido está em voo.
  bool isUpdating(String orderId) => _updatingIds.contains(orderId);

  /// Liga a rotina. Se estava pausada, consulta assim que o ciclo acordar.
  void resume() {
    if (_disposed || _active) return;
    _active = true;
    if (_inFlight) _refreshSoon = true;
    _completeSignal();
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  /// Segura a próxima consulta. A que já está em voo pode concluir.
  void pause() {
    _active = false;
    _refreshSoon = false;
  }

  /// Repete a consulta. Não inicia outra se já existe uma em voo.
  Future<void> retry() {
    if (_disposed) return Future<void>.value();
    return _fetch(background: _hasLoaded);
  }

  /// Limpa o banner do último avanço falho.
  void clearActionError() {
    if (_disposed || (_actionError == null && _actionFailure == null)) return;
    _actionError = null;
    _actionFailure = null;
    _notify();
  }

  /// Avança um passo o status do pedido. Só um PATCH por id por vez.
  ///
  /// Devolve o pedido atualizado em sucesso; `null` se falhou, foi ignorado
  /// ou o pedido saiu da fila (`finished`).
  Future<Order?> advanceStatus(String orderId) async {
    if (_disposed || _updatingIds.contains(orderId)) return null;

    Order? current;
    for (final order in _orders) {
      if (order.id == orderId) {
        current = order;
        break;
      }
    }
    final next = current?.status.next;
    if (current == null || next == null) return null;

    _updatingIds.add(orderId);
    _actionError = null;
    _actionFailure = null;
    _notify();

    try {
      final result = await _repository.updateStatus(id: orderId, status: next);
      if (_disposed) return null;
      final updated = result.order;
      if (updated != null) {
        _applyUpdatedOrder(updated);
        if (updated.status == OrderStatus.finished) return null;
        return updated;
      }
      await _handleAdvanceFailure(
        orderId,
        result.message,
        result.failure ?? DataFailure.unavailable,
      );
      return null;
    } catch (error, stackTrace) {
      if (_disposed) return null;
      await _handleAdvanceFailure(orderId, unexpectedAdvanceMessage, DataFailure.unavailable);
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'orders queue view model',
            context: ErrorDescription('ao avançar o status do pedido'),
          ),
        );
      }
      return null;
    } finally {
      if (!_disposed) {
        _updatingIds.remove(orderId);
        _notify();
      }
    }
  }

  Future<void> _handleAdvanceFailure(String orderId, String? message, DataFailure failure) async {
    final text = message == null || message.isEmpty ? unexpectedAdvanceMessage : message;
    if (failure == DataFailure.notFound) {
      _removeOrder(orderId);
      _actionError = text;
      _actionFailure = failure;
      _notify();
      return;
    }
    if (failure == DataFailure.conflict) {
      _actionError = staleStatusMessage;
      _actionFailure = failure;
      _notify();
      await _fetch(background: true);
      return;
    }
    _actionError = text;
    _actionFailure = failure;
    _notify();
  }

  void _applyUpdatedOrder(Order updated) {
    _actionError = null;
    _actionFailure = null;
    if (updated.status == OrderStatus.finished) {
      _removeOrder(updated.id);
      return;
    }
    final next = <Order>[];
    var found = false;
    for (final order in _orders) {
      if (order.id == updated.id) {
        next.add(updated);
        found = true;
      } else {
        next.add(order);
      }
    }
    if (!found) next.add(updated);
    _orders = _sorted(next);
    _notify();
  }

  void _removeOrder(String orderId) {
    _orders = List.unmodifiable([
      for (final order in _orders)
        if (order.id != orderId) order,
    ]);
  }

  Future<void> _run() async {
    while (!_disposed) {
      if (_active) {
        await _fetch(background: _hasLoaded);
      }
      if (_disposed) return;
      if (_active && _refreshSoon) {
        _refreshSoon = false;
        continue;
      }
      await _waitForNextPoll();
    }
  }

  Future<void> _waitForNextPoll() async {
    final signal = Completer<void>();
    _signal = signal;
    try {
      if (!_active) {
        await signal.future;
        return;
      }
      await Future.any<void>([_delay(pollInterval), signal.future]);
    } finally {
      if (identical(_signal, signal)) _signal = null;
    }
  }

  Future<void> _fetch({required bool background}) async {
    if (_disposed || _inFlight) return;
    _inFlight = true;
    final showBlockingLoading = !background && !_hasLoaded;
    if (showBlockingLoading) {
      _loading = true;
      _errorMessage = null;
      _failure = null;
      _notify();
    }

    try {
      final result = await _repository.list();
      if (_disposed) return;
      final orders = result.orders;
      if (orders != null) {
        _showOrders(orders);
        return;
      }
      final message = result.message;
      _showFailure(
        message == null || message.isEmpty ? unexpectedFailureMessage : message,
        result.failure ?? DataFailure.unavailable,
      );
    } catch (error, stackTrace) {
      if (_disposed) return;
      _showFailure(unexpectedFailureMessage, DataFailure.unavailable);
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'orders queue view model',
            context: ErrorDescription('ao carregar a fila de pedidos'),
          ),
        );
      }
    } finally {
      _inFlight = false;
    }
  }

  void _showOrders(List<Order> orders) {
    final sorted = _sorted(orders);
    final changed =
        !_hasLoaded ||
        _loading ||
        _errorMessage != null ||
        _refreshError != null ||
        _failure != null ||
        !_sameOrders(_orders, sorted);
    _orders = sorted;
    _hasLoaded = true;
    _loading = false;
    _errorMessage = null;
    _refreshError = null;
    _failure = null;
    if (changed) _notify();
  }

  void _showFailure(String message, DataFailure failure) {
    _loading = false;
    if (_hasLoaded) {
      if (_refreshError == message && _failure == failure) return;
      _refreshError = message;
      _failure = failure;
      _notify();
      return;
    }
    _errorMessage = message;
    _refreshError = null;
    _failure = failure;
    _notify();
  }

  List<Order> _sorted(List<Order> orders) {
    final active = [
      for (final order in orders)
        if (order.status != OrderStatus.finished) order,
    ];
    active.sort((a, b) {
      final byPriority = _queuePriority(a.status).compareTo(_queuePriority(b.status));
      if (byPriority != 0) return byPriority;
      final byTime = a.createdAt.compareTo(b.createdAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return List.unmodifiable(active);
  }

  /// Menor valor aparece antes. `ready` sobe; depois `preparing`; o restante por tempo.
  static int _queuePriority(OrderStatus status) => switch (status) {
    OrderStatus.ready => 0,
    OrderStatus.preparing => 1,
    OrderStatus.received || OrderStatus.finished => 2,
  };

  void _completeSignal() {
    final signal = _signal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _refreshSoon = false;
    _completeSignal();
    super.dispose();
  }
}

bool _sameOrders(List<Order> current, List<Order> next) {
  if (current.length != next.length) return false;
  for (var index = 0; index < current.length; index++) {
    if (current[index] != next[index]) return false;
  }
  return true;
}
