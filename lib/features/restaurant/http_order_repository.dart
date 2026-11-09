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

  static const validationErrorCode = 'VALIDATION_ERROR';

  static const productNotFoundCode = 'PRODUCT_NOT_FOUND';

  static const routeNotFoundCode = 'NOT_FOUND';

  /// Código do hook `onRequest` quando o token está ausente ou é inválido.
  static const unauthorizedCode = 'UNAUTHORIZED';

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
  Future<OrderLookup> findById(String id) async {
    if (id.trim().isEmpty) {
      return const OrderLookup.unavailable(
        'Identificador do pedido inválido',
        failure: DataFailure.validation,
      );
    }

    try {
      final body = await _apiClient.getJson('/orders/${Uri.encodeComponent(id)}');
      return OrderLookup.ready(Order.fromJson(body));
    } on ApiException catch (error) {
      return OrderLookup.unavailable(error.message, failure: error.failure, detail: error.detail);
    } on FormatException {
      return const OrderLookup.unavailable(unexpectedResponseMessage);
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
      final created = Order.fromJson(response);
      return OrderSubmission.created(await _withPublicNumber(created));
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

  /// Completa um 201 antigo que trouxe `id` e não trouxe `orderNumber`.
  ///
  /// A consulta é `GET /orders/:id`, com o mesmo cliente autenticado. O
  /// número entra na fotografia já confirmada. Outro status ou outros itens
  /// lidos agora não substituem essa fotografia. Falha operacional, corpo sem
  /// número ou pedido diferente não alteram o sucesso do POST e não disparam
  /// outro POST. `Error` segue adiante.
  Future<Order> _withPublicNumber(Order order) async {
    if (order.orderNumber != null) return order;
    try {
      final lookup = await findById(order.id);
      final recovered = lookup.order;
      if (recovered == null || recovered.id != order.id) return order;
      final number = recovered.orderNumber;
      if (number == null) return order;
      return order.withOrderNumber(number);
    } on Exception {
      return order;
    }
  }

  /// Classifica o POST que já saiu com ou sem `Idempotency-Key`.
  ///
  /// Com a chave, só [validationErrorCode] em 400 e [productNotFoundCode] em
  /// 404 provam que nada foi gravado. [routeNotFoundCode] não entra aí: pode
  /// ser rota, proxy ou contrato incompatível. 409 sem código e 500 sem código
  /// bloqueiam, porque o código perdido pode ser conflito ou chave órfã. O
  /// restante preserva a chave para reenvio manual.
  OrderSubmission _fromApi(ApiException error, {required bool sentKey}) {
    final status = error.statusCode;
    final code = _usableCode(error.code);

    if (code == idempotencyConflictCode || (sentKey && status == 409 && code == null)) {
      return const OrderSubmission.blocked(
        idempotencyConflictMessage,
        failure: DataFailure.conflict,
      );
    }
    if (code == idempotencyInvalidCode) {
      return const OrderSubmission.blocked(
        idempotencyInvalidMessage,
        failure: DataFailure.unavailable,
      );
    }
    // Corpo vazio, JSON inválido ou leitura interrompida apagam o código. Não
    // inventamos `error.code`. Sem ele, HTTP 500 não distingue
    // IDEMPOTENCY_STATE_INVALID de INTERNAL_ERROR. A chave enviada não volta
    // a ser usada e outra não é criada. 502, 503, timeout sem status e 500
    // com outro código ficam fora desta decisão.
    if (sentKey && status == 500 && code == null) {
      return const OrderSubmission.blocked(
        OrderSubmission.unreadableServerErrorMessage,
        failure: DataFailure.unavailable,
      );
    }

    // O hook atual responde 401 UNAUTHORIZED antes de registrar o pedido.
    // Sem esse código, um 401 não prova a mesma coisa e segue incerto.
    if (!error.outcomeUncertain && status == 401 && code == unauthorizedCode) {
      return OrderSubmission.failed(
        OrderSubmission.unauthorizedRejectionMessage,
        failure: DataFailure.unavailable,
        detail: error.detail ?? error.message,
        retainsIntent: true,
      );
    }

    if (!error.outcomeUncertain && _provenWithoutEffect(status, code)) {
      return OrderSubmission.failed(
        error.message,
        failure: status == 404 ? DataFailure.notFound : DataFailure.validation,
        detail: error.detail,
      );
    }

    // 404 NOT_FOUND não prova ausência do pedido. Com a chave enviada, nenhum
    // outro 4xx/5xx entra na limpeza da intenção.
    final accepted = status != null && status >= 200 && status < 300;
    final unproven = status != null && status >= 500;
    if (code == routeNotFoundCode || sentKey || error.outcomeUncertain || accepted || unproven) {
      return OrderSubmission.failed(
        OrderSubmission.uncertainOutcomeMessage,
        failure: DataFailure.uncertain,
        detail: error.detail ?? error.message,
        outcomeUncertain: true,
      );
    }
    return OrderSubmission.failed(error.message, failure: error.failure, detail: error.detail);
  }

  String? _usableCode(String? code) {
    final trimmed = code?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  bool _provenWithoutEffect(int? status, String? code) {
    return (status == 400 && code == validationErrorCode) ||
        (status == 404 && code == productNotFoundCode);
  }
}
