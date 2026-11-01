import '../../core/domain/cart_item.dart';
import '../../core/domain/data_failure.dart';
import '../../core/domain/order.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'order_repository.dart';

/// Repository concreto de `GET /orders` e `POST /orders`.
///
/// A listagem não envia `status` nem `table`; a fila pede a lista inteira.
/// A criação envia mesa e itens. `totalCents` é o da resposta, não uma soma
/// local.
class HttpOrderRepository implements OrderRepository {
  HttpOrderRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Mensagem estável para corpo JSON que não é a lista do contrato.
  static const unexpectedResponseMessage = 'Resposta inesperada da API';

  static const emptyTableMessage = OrderRequest.emptyTableMessage;

  static const emptyItemsMessage = OrderRequest.emptyItemsMessage;

  static const invalidItemMessage = OrderRequest.invalidItemMessage;

  static const idempotencyConflictCode = 'IDEMPOTENCY_KEY_CONFLICT';

  static const idempotencyInvalidCode = 'IDEMPOTENCY_STATE_INVALID';

  static const idempotencyConflictMessage = OrderSubmission.idempotencyConflictMessage;

  static const idempotencyInvalidMessage = OrderSubmission.idempotencyInvalidMessage;

  @override
  Future<OrderList> list() async {
    try {
      final body = await _apiClient.getJson('/orders');
      if (body is! List) return const OrderList.unavailable(unexpectedResponseMessage);

      final orders = <Order>[for (final item in body) Order.fromJson(item as Object?)];
      return OrderList.ready(orders);
    } on ApiException catch (error) {
      return OrderList.unavailable(error.message, failure: error.failure, detail: error.detail);
    } on FormatException {
      return const OrderList.unavailable(unexpectedResponseMessage);
    }
  }

  @override
  Future<OrderSubmission> create({
    required String table,
    required List<CartItem> items,
    String? idempotencyKey,
    Map<String, Object?>? body,
  }) async {
    final rejected = OrderRequest.rejection(table: table, items: items);
    if (rejected != null) return rejected;

    final payload = body ?? OrderRequest.body(table: table, items: items);
    final key = idempotencyKey?.trim();
    final headers = key == null || key.isEmpty ? null : <String, String>{'Idempotency-Key': key};

    try {
      final response = await _apiClient.postJson('/orders', payload, headers: headers);
      return OrderSubmission.created(Order.fromJson(response));
    } on ApiException catch (error) {
      return _fromApi(error, sentKey: headers != null);
    } on FormatException catch (error) {
      return OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        detail: error.message,
        outcomeUncertain: true,
      );
    }
  }

  OrderSubmission _fromApi(ApiException error, {required bool sentKey}) {
    if (error.code == idempotencyConflictCode) {
      return const OrderSubmission.blocked(
        idempotencyConflictMessage,
        failure: DataFailure.conflict,
      );
    }
    if (error.code == idempotencyInvalidCode) {
      return const OrderSubmission.blocked(
        idempotencyInvalidMessage,
        failure: DataFailure.unavailable,
      );
    }

    final status = error.statusCode;
    final code = error.code?.trim();
    final missingCode = code == null || code.isEmpty;
    // 409 sem código utilizável não prova que a chave enviada está livre.
    if (sentKey && status == 409 && missingCode) {
      return const OrderSubmission.blocked(
        idempotencyConflictMessage,
        failure: DataFailure.conflict,
      );
    }

    // O contrato só documenta chave órfã em HTTP 500 com
    // IDEMPOTENCY_STATE_INVALID. Corpo vazio, JSON inválido ou leitura
    // interrompida apagam esse código. Não inventamos `error.code`. Sem ele,
    // a chave enviada não volta a ser usada e outra não é criada. 502, 503,
    // timeout sem status e 500 com outro código ficam fora desta decisão.
    if (sentKey && status == 500 && missingCode) {
      return const OrderSubmission.blocked(
        OrderSubmission.unreadableServerErrorMessage,
        failure: DataFailure.unavailable,
      );
    }

    final accepted = status != null && status >= 200 && status < 300;
    // 5xx com código diferente, ou status que o contrato não usa para chave
    // órfã, não prova que o pedido deixou de ser criado.
    final unproven = status != null && status >= 500;
    if (error.outcomeUncertain || accepted || unproven) {
      return OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        detail: error.detail ?? error.message,
        outcomeUncertain: true,
      );
    }
    return OrderSubmission.failed(error.message, failure: error.failure, detail: error.detail);
  }
}
