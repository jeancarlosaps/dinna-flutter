import 'package:flutter/foundation.dart';

import '../../../core/domain/cart_item.dart';
import '../../../core/domain/data_failure.dart';
import '../../../core/domain/order.dart';
import '../../restaurant/order_repository.dart';

/// Estado do envio para a View. Ela não lê HTTP.
enum OrderSubmissionStatus { idle, submitting, succeeded, failed }

/// Envio do pedido: ViewModel → [OrderRepository.create].
///
/// Não guarda carrinho. Quem chama entrega a mesa e os [CartItem] no [submit].
/// [shouldClearCart] fica verdadeiro só depois que a API confirma o pedido.
/// A tela do carrinho, quando existir, limpa os itens nesse caso. Falha,
/// inclusive resultado incerto, não pede limpeza e não apaga item.
///
/// Uma chamada durante o envio é ignorada. Não há nova tentativa automática:
/// outra chamada só acontece se quem usa o ViewModel pedir de novo, depois
/// que a anterior terminou. Depois do [dispose], a resposta pendente não
/// altera estado nem notifica.
class OrderSubmissionViewModel extends ChangeNotifier {
  OrderSubmissionViewModel(this._repository);

  final OrderRepository _repository;

  /// Mensagem quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedFailureMessage = 'Não foi possível enviar o pedido';

  OrderSubmissionStatus _status = OrderSubmissionStatus.idle;
  Order? _order;
  String? _errorMessage;
  DataFailure? _failure;
  bool _outcomeUncertain = false;
  bool _disposed = false;

  OrderSubmissionStatus get status => _status;

  /// Pedido devolvido pela API. Preenchido só em [OrderSubmissionStatus.succeeded].
  Order? get order => _order;

  /// Preenchida só quando o envio falha.
  String? get errorMessage => _errorMessage;

  /// Nula enquanto não houve falha.
  DataFailure? get failure => _failure;

  /// Verdadeiro quando o POST pode ter sido aplicado sem confirmação.
  bool get outcomeUncertain => _outcomeUncertain;

  bool get isSubmitting => _status == OrderSubmissionStatus.submitting;

  /// Contrato com o carrinho que ainda não está ligado a esta entrega.
  ///
  /// Só a confirmação da API liga este sinal. Esta classe não apaga item.
  bool get shouldClearCart => _status == OrderSubmissionStatus.succeeded && _order != null;

  /// Envia [items] para a mesa [table].
  ///
  /// Ignora a chamada se já existe um envio em andamento ou se o ViewModel
  /// foi descartado. Não repete o POST por conta própria.
  Future<void> submit({required String table, required List<CartItem> items}) async {
    if (_disposed || _status == OrderSubmissionStatus.submitting) return;

    _status = OrderSubmissionStatus.submitting;
    _order = null;
    _errorMessage = null;
    _failure = null;
    _outcomeUncertain = false;
    _notify();

    try {
      final result = await _repository.create(table: table, items: items);
      if (_disposed) return;
      final order = result.order;
      if (order == null) {
        final uncertain = result.outcomeUncertain || result.failure == DataFailure.uncertain;
        _publish(
          status: OrderSubmissionStatus.failed,
          message: _visibleMessage(result.message, uncertain: uncertain),
          failure: result.failure ?? (uncertain ? DataFailure.uncertain : DataFailure.unavailable),
          outcomeUncertain: uncertain,
        );
        return;
      }
      _publish(status: OrderSubmissionStatus.succeeded, order: order);
    } catch (error, stackTrace) {
      if (_disposed) return;
      _publish(
        status: OrderSubmissionStatus.failed,
        message: unexpectedFailureMessage,
        failure: DataFailure.unavailable,
      );
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'order submission view model',
            context: ErrorDescription('ao enviar o pedido'),
          ),
        );
      }
    }
  }

  String _visibleMessage(String? message, {required bool uncertain}) {
    if (message != null && message.trim().isNotEmpty) return message;
    if (uncertain) return OrderSubmission.uncertainOutcomeMessage;
    return unexpectedFailureMessage;
  }

  void _publish({
    required OrderSubmissionStatus status,
    Order? order,
    String? message,
    DataFailure? failure,
    bool outcomeUncertain = false,
  }) {
    if (_disposed) return;
    _status = status;
    _order = order;
    _errorMessage = message;
    _failure = failure;
    _outcomeUncertain = outcomeUncertain;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
