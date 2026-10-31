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

  static const emptyTableMessage = 'Informe a mesa';

  static const emptyItemsMessage = 'O pedido precisa de ao menos um item';

  static const invalidItemMessage = 'Item do pedido inválido';

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
  Future<OrderSubmission> create({required String table, required List<CartItem> items}) async {
    final rejected = _reject(table, items);
    if (rejected != null) return rejected;

    final payload = <String, Object?>{
      'table': table,
      'items': <Object?>[for (final item in items) item.toOrderItem().toJson()],
    };

    try {
      final body = await _apiClient.postJson('/orders', payload);
      return OrderSubmission.created(Order.fromJson(body));
    } on ApiException catch (error) {
      return _fromApi(error);
    } on FormatException catch (error) {
      return OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        detail: error.message,
        outcomeUncertain: true,
      );
    }
  }

  /// [CartItem] já recusa productId vazio e quantity menor que 1.
  /// Identificador só com espaço ainda passa no construtor e para aqui.
  OrderSubmission? _reject(String table, List<CartItem> items) {
    if (table.trim().isEmpty) {
      return const OrderSubmission.failed(emptyTableMessage, failure: DataFailure.validation);
    }
    if (items.isEmpty) {
      return const OrderSubmission.failed(emptyItemsMessage, failure: DataFailure.validation);
    }
    for (final item in items) {
      if (item.productId.trim().isEmpty || item.quantity < 1) {
        return const OrderSubmission.failed(invalidItemMessage, failure: DataFailure.validation);
      }
    }
    return null;
  }

  OrderSubmission _fromApi(ApiException error) {
    final status = error.statusCode;
    final accepted = status != null && status >= 200 && status < 300;
    if (error.outcomeUncertain || accepted) {
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
