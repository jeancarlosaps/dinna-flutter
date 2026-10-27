import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/domain/order.dart';
import 'order_repository.dart';

/// Fila do restaurante: ViewModel → [OrderRepository]. Não conhece HTTP.
///
/// O polling é uma única rotina por instância. [defaultPollInterval] é o
/// intervalo entre consultas bem iniciadas. Enquanto uma consulta está em
/// voo, outra não começa. [pause] segura a próxima consulta; [resume] busca
/// na hora. Depois do [dispose], a resposta pendente não altera estado nem
/// notifica.
///
/// A ordenação é local: `createdAt` crescente e, no empate, `id` em ordem
/// lexicográfica. É a mesma chave do `ORDER BY created_at ASC, o.id ASC` da API.
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

  static Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

  List<Order> _orders = const [];
  bool _hasLoaded = false;
  bool _loading = false;
  String? _errorMessage;
  String? _refreshError;
  bool _active = false;
  bool _started = false;
  bool _disposed = false;
  bool _inFlight = false;
  Completer<void>? _signal;

  /// Pedidos já ordenados. Vazio antes da primeira resposta com sucesso.
  List<Order> get orders => _orders;

  /// Carregamento que ocupa a tela. Atualização com dados na tela não liga isto.
  bool get isLoading => _loading;

  /// Houve ao menos uma lista válida. Erro de atualização não apaga este fato.
  bool get hasLoaded => _hasLoaded;

  /// Erro da carga inicial ou do retry, quando ainda não há lista para mostrar.
  String? get errorMessage => _errorMessage;

  /// Falha de uma atualização depois que a lista já existe. A lista permanece.
  String? get refreshError => _refreshError;

  /// Lista válida e sem pedidos. Erro inicial não é fila vazia.
  bool get isEmpty => _hasLoaded && _orders.isEmpty && _errorMessage == null;

  /// Liga a rotina. Se estava pausada, consulta assim que o ciclo acordar.
  void resume() {
    if (_disposed || _active) return;
    _active = true;
    _completeSignal();
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  /// Segura a próxima consulta. A que já está em voo pode concluir.
  void pause() {
    _active = false;
  }

  /// Repete a consulta. Não inicia outra se já existe uma em voo.
  Future<void> retry() {
    if (_disposed) return Future<void>.value();
    return _fetch(background: _hasLoaded);
  }

  Future<void> _run() async {
    while (!_disposed) {
      if (_active) {
        await _fetch(background: _hasLoaded);
      }
      if (_disposed) return;
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
      _showFailure(message == null || message.isEmpty ? unexpectedFailureMessage : message);
    } catch (error, stackTrace) {
      if (_disposed) return;
      _showFailure(unexpectedFailureMessage);
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
        !_sameOrders(_orders, sorted);
    _orders = sorted;
    _hasLoaded = true;
    _loading = false;
    _errorMessage = null;
    _refreshError = null;
    if (changed) _notify();
  }

  void _showFailure(String message) {
    _loading = false;
    if (_hasLoaded) {
      if (_refreshError == message) return;
      _refreshError = message;
      _notify();
      return;
    }
    _errorMessage = message;
    _refreshError = null;
    _notify();
  }

  List<Order> _sorted(List<Order> orders) {
    final sorted = [...orders]
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
    return List.unmodifiable(sorted);
  }

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
