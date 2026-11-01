import 'package:flutter/foundation.dart';

import '../../../core/domain/cart_item.dart';
import '../../../core/domain/data_failure.dart';
import '../../../core/domain/order.dart';
import '../../restaurant/order_repository.dart';

/// Estado do envio para a View. Ela não lê HTTP.
enum OrderSubmissionStatus { idle, submitting, succeeded, failed }

/// Envio do pedido: ViewModel → [OrderRepository.create].
///
/// Não guarda carrinho. [submit] fotografa a mesa e os [CartItem] e envia
/// essa cópia. [shouldClearCart] fica verdadeiro só depois que a API confirma
/// o pedido. A limpeza remove [confirmedItems], não o carrinho inteiro: itens
/// incluídos ou alterados depois do [submit] ficam de fora da fotografia.
/// Falha e resultado incerto não pedem limpeza.
///
/// [OrderSubmissionStatus.failed] com [outcomeUncertain] não é falha
/// definitiva. [isDefiniteFailure] é o erro confirmado. Uma chamada durante
/// o envio é ignorada. Não há nova tentativa automática. Depois do [dispose],
/// a resposta pendente não altera estado nem notifica.
class OrderSubmissionViewModel extends ChangeNotifier {
  OrderSubmissionViewModel(this._repository);

  final OrderRepository _repository;

  /// Mensagem quando uma falha confirmada chega sem texto utilizável.
  static const unexpectedFailureMessage = 'Não foi possível enviar o pedido';

  /// Orientação junto do resultado incerto. Não afirma que o pedido falhou.
  ///
  /// A tela mostra este texto e não oferece "Tentar novamente" no mesmo passo.
  static const verifyBeforeRetryGuidance =
      'Confira com o restaurante se o pedido chegou antes de tentar de novo.';

  OrderSubmissionStatus _status = OrderSubmissionStatus.idle;
  Order? _order;
  String? _errorMessage;
  DataFailure? _failure;
  bool _outcomeUncertain = false;
  List<CartItem>? _confirmedItems;
  String? _confirmedTable;
  bool _disposed = false;

  OrderSubmissionStatus get status => _status;

  /// Pedido devolvido pela API. Preenchido só em [OrderSubmissionStatus.succeeded].
  Order? get order => _order;

  /// Preenchida só quando o envio falha.
  String? get errorMessage => _errorMessage;

  /// Nula enquanto não houve falha.
  DataFailure? get failure => _failure;

  /// Verdadeiro quando o POST pode ter sido aplicado sem confirmação.
  ///
  /// A tela não trata este caso como falha definitiva e não limpa o carrinho.
  bool get outcomeUncertain => _outcomeUncertain;

  /// Erro com resposta confirmada ou validação local.
  ///
  /// Resultado incerto fica de fora: [status] pode ser
  /// [OrderSubmissionStatus.failed] e este getter continua falso.
  bool get isDefiniteFailure => _status == OrderSubmissionStatus.failed && !_outcomeUncertain;

  bool get isSubmitting => _status == OrderSubmissionStatus.submitting;

  /// Itens da fotografia que a API confirmou. Nulo sem sucesso.
  ///
  /// A limpeza tira só esta lista. Esta classe não altera o carrinho.
  List<CartItem>? get confirmedItems => _confirmedItems;

  /// Mesa da mesma fotografia. Nula sem sucesso.
  String? get confirmedTable => _confirmedTable;

  /// Só a confirmação da API liga este sinal. Esta classe não apaga item.
  bool get shouldClearCart =>
      _status == OrderSubmissionStatus.succeeded && _order != null && _confirmedItems != null;

  /// A View só chama [submit] quando este sinal é verdadeiro.
  ///
  /// Vale para o primeiro envio e para a nova tentativa depois de uma rejeição
  /// confirmada. Fica falso durante o envio, depois do sucesso e quando o
  /// resultado é incerto: a tela não dispara outro POST nesses casos.
  bool get canRequestSubmit =>
      !_disposed &&
      !_outcomeUncertain &&
      (_status == OrderSubmissionStatus.idle || isDefiniteFailure);

  /// Envia [items] para a mesa [table].
  ///
  /// Ignora a chamada se já existe um envio em andamento ou se o ViewModel
  /// foi descartado. Não repete o POST por conta própria.
  Future<void> submit({required String table, required List<CartItem> items}) async {
    if (_disposed || _status == OrderSubmissionStatus.submitting) return;

    final submittedItems = List<CartItem>.unmodifiable(items);
    final submittedTable = table;
    _status = OrderSubmissionStatus.submitting;
    _order = null;
    _errorMessage = null;
    _failure = null;
    _outcomeUncertain = false;
    _confirmedItems = null;
    _confirmedTable = null;
    _notify();

    try {
      final result = await _repository.create(table: submittedTable, items: submittedItems);
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
      _publish(
        status: OrderSubmissionStatus.succeeded,
        order: order,
        confirmedItems: submittedItems,
        confirmedTable: submittedTable,
      );
    } catch (error, stackTrace) {
      if (_disposed) return;
      // A exceção escapou do repositório. Não há status que prove a rejeição.
      _publish(
        status: OrderSubmissionStatus.failed,
        message: OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        outcomeUncertain: true,
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
    List<CartItem>? confirmedItems,
    String? confirmedTable,
  }) {
    if (_disposed) return;
    _status = status;
    _order = order;
    _errorMessage = message;
    _failure = failure;
    _outcomeUncertain = outcomeUncertain;
    _confirmedItems = confirmedItems;
    _confirmedTable = confirmedTable;
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
