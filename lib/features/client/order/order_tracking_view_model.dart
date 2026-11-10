import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/data_failure.dart';
import '../../../core/domain/order.dart';
import '../../../core/domain/order_status.dart';
import '../../restaurant/order_repository.dart';

/// Acompanhamento do pedido pelo cliente: ViewModel → [OrderRepository.findById].
///
/// Consulta o pedido a cada [pollInterval] enquanto a tela está ativa, uma
/// consulta por vez. [pause] segura a próxima (app em segundo plano) e
/// [resume] consulta na hora. Para de consultar quando o pedido chega a
/// [OrderStatus.finished] ou quando a API responde que ele não existe. Falha
/// numa atualização mantém o último status na tela. Depois do [dispose], a
/// resposta pendente não altera estado nem notifica.
class OrderTrackingViewModel extends ChangeNotifier {
  OrderTrackingViewModel(
    this._repository, {
    required this.orderId,
    this.pollInterval = defaultPollInterval,
    this.delay,
  });

  final OrderRepository _repository;
  final String orderId;
  final Duration pollInterval;

  /// Espera entre consultas, para testes. Nulo usa um [Timer] que o
  /// [dispose] cancela.
  final Future<void> Function(Duration duration)? delay;

  /// Intervalo entre consultas automáticas do status.
  static const defaultPollInterval = Duration(seconds: 5);

  /// Mensagem quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedFailureMessage = 'Não foi possível consultar o pedido.';

  Order? _order;
  String? _errorMessage;
  String? _refreshError;
  bool _notFound = false;
  bool _active = false;
  bool _started = false;
  bool _inFlight = false;
  bool _disposed = false;
  Completer<void>? _signal;
  Timer? _timer;

  /// Último pedido lido. Nulo até a primeira consulta com sucesso.
  Order? get order => _order;

  /// Ainda não há pedido, erro nem resposta de pedido inexistente.
  bool get isLoading => _order == null && _errorMessage == null && !_notFound;

  /// Há uma consulta em voo.
  bool get isFetching => _inFlight;

  /// Falha da primeira consulta, quando ainda não há pedido para mostrar.
  String? get errorMessage => _errorMessage;

  /// Falha de uma atualização. O último status continua na tela.
  String? get refreshError => _refreshError;

  /// A API respondeu que o pedido não existe.
  bool get notFound => _notFound;

  /// Não há mais o que acompanhar: pedido finalizado ou inexistente.
  bool get isDone => _notFound || _order?.status == OrderStatus.finished;

  /// Liga as consultas. Se estavam pausadas, consulta na hora.
  void resume() {
    if (_disposed || _active) return;
    _active = true;
    _wake();
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  /// Segura a próxima consulta. A que já está em voo pode concluir.
  void pause() {
    _active = false;
  }

  /// Consulta de novo, por exemplo depois de uma falha. Não inicia outra se
  /// já existe uma em voo.
  Future<void> retry() => _fetch();

  Future<void> _run() async {
    while (!_disposed && !isDone) {
      if (_active) await _fetch();
      if (_disposed || isDone) return;
      final signal = Completer<void>();
      _signal = signal;
      await Future.any([_waitInterval(), signal.future]);
      _signal = null;
    }
  }

  Future<void> _waitInterval() {
    final wait = delay;
    if (wait != null) return wait(pollInterval);
    final done = Completer<void>();
    _timer = Timer(pollInterval, done.complete);
    return done.future;
  }

  void _wake() {
    final signal = _signal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<void> _fetch() async {
    if (_disposed || _inFlight || isDone) return;
    _inFlight = true;
    notifyListeners();

    OrderLookup lookup;
    try {
      lookup = await _repository.findById(orderId);
    } catch (error, stackTrace) {
      lookup = const OrderLookup.unavailable(unexpectedFailureMessage);
      if (kDebugMode && !_disposed) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'order tracking view model',
            context: ErrorDescription('ao consultar o status do pedido'),
          ),
        );
      }
    }
    _inFlight = false;
    if (_disposed) return;

    final found = lookup.order;
    if (found != null) {
      _order = found;
      _errorMessage = null;
      _refreshError = null;
    } else if (lookup.failure == DataFailure.notFound) {
      _notFound = true;
      _errorMessage = null;
      _refreshError = null;
    } else {
      final message = lookup.message;
      final text = message == null || message.isEmpty ? unexpectedFailureMessage : message;
      if (_order == null) {
        _errorMessage = text;
      } else {
        _refreshError = text;
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _wake();
    super.dispose();
  }
}
