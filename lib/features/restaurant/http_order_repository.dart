import '../../core/domain/order.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'order_repository.dart';

/// Repository concreto do `GET /orders`, usando o [ApiClient] como Service.
///
/// A consulta não envia `status` nem `table`. O contrato aceita esses filtros;
/// a fila pede a lista inteira.
class HttpOrderRepository implements OrderRepository {
  HttpOrderRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Mensagem estável para corpo JSON que não é a lista do contrato.
  static const unexpectedResponseMessage = 'Resposta inesperada da API';

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
}
