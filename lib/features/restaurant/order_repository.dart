import '../../core/domain/cart_item.dart';
import '../../core/domain/data_failure.dart';
import '../../core/domain/order.dart';
import '../../core/domain/order_status.dart';

/// Fila já traduzida para o ViewModel.
///
/// Não carrega status HTTP nem exceção de transporte. Lista vazia é sucesso:
/// [orders] vem vazio e [message] fica nula. Falha deixa [orders] nulo.
/// [failure] classifica essa falha para a apresentação.
class OrderList {
  OrderList.ready(List<Order> orders) : this._(orders: List.unmodifiable(orders));

  const OrderList.unavailable(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
  }) : this._(message: message, failure: failure, detail: detail);

  const OrderList._({this.orders, this.message, this.failure, this.detail});

  /// `null` quando a listagem falhou. Lista vazia significa fila sem pedidos.
  final List<Order>? orders;

  /// Preenchida só quando a listagem falha.
  final String? message;

  /// Nula quando a lista carregou.
  final DataFailure? failure;

  /// Causa técnica. A tela usa [message].
  final String? detail;
}

/// Pedido criado, ou a falha já traduzida para a tela.
///
/// Não carrega status HTTP nem exceção de transporte. Sucesso traz [order],
/// com o total que a API calculou. Falha deixa [order] nulo.
///
/// [shouldClearCart] fica verdadeiro só quando a API confirmou o pedido.
/// Os itens a remover são a fotografia em `OrderSubmissionViewModel.confirmedItems`,
/// não o carrinho inteiro. Falha e resultado incerto não pedem limpeza.
/// Esta classe não guarda nem apaga item.
class OrderSubmission {
  OrderSubmission.created(Order order) : this._(order: order);

  const OrderSubmission.failed(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
    bool outcomeUncertain = false,
    bool retainsIntent = false,
  }) : this._(
         message: message,
         failure: failure,
         detail: detail,
         outcomeUncertain: outcomeUncertain,
         retainsIntent: retainsIntent,
       );

  /// A chave não pode ser reenviada nem trocada por outra.
  ///
  /// Cobre conflito de payload, chave órfã e o mesmo bloqueio decidido no app.
  const OrderSubmission.blocked(
    String message, {
    DataFailure failure = DataFailure.conflict,
    String? detail,
  }) : this._(message: message, failure: failure, detail: detail, resendBlocked: true);

  const OrderSubmission._({
    this.order,
    this.message,
    this.failure,
    this.detail,
    this.outcomeUncertain = false,
    this.resendBlocked = false,
    this.retainsIntent = false,
  });

  /// Texto quando o POST pode ter sido aplicado e a confirmação não chegou.
  ///
  /// Não afirma que o pedido falhou. A mesma frase está em
  /// `ApiClient.uncertainOutcomeMessage`; o client não importa esta feature.
  static const uncertainOutcomeMessage =
      'Não foi possível confirmar o envio. O pedido pode ter sido registrado.';

  /// Mesma chave com outro payload. A chave continua no primeiro pedido.
  static const idempotencyConflictMessage =
      'Esta tentativa já está ligada a outro envio. Confira com o restaurante se o pedido chegou.';

  /// A chave existe sem o pedido correspondente. Outra chave não é criada daqui.
  static const idempotencyInvalidMessage =
      'Não foi possível confirmar o pedido desta tentativa. Confira com o restaurante.';

  /// HTTP 500 depois de enviar a chave, sem `error.code` utilizável.
  ///
  /// O contrato só usa 500 para `IDEMPOTENCY_STATE_INVALID` e `INTERNAL_ERROR`.
  /// Sem o código, os dois se confundem. Este texto não inventa o código e
  /// não afirma que o pedido deixou de existir.
  static const unreadableServerErrorMessage =
      'A resposta do servidor não trouxe o código do erro. Esta tentativa não será reenviada. Confira com o restaurante.';

  /// HTTP 401 `UNAUTHORIZED` do hook atual da API.
  ///
  /// O acesso foi recusado antes do registro do pedido. Não é resultado
  /// incerto e não autoriza outra chave.
  static const unauthorizedRejectionMessage =
      'O envio foi recusado. A API não aceitou o acesso e o pedido não foi registrado.';

  /// `null` quando a criação falhou.
  final Order? order;

  /// Preenchida só quando a criação falha.
  final String? message;

  /// Nula quando o pedido foi criado.
  final DataFailure? failure;

  /// Causa técnica. A tela usa [message].
  final String? detail;

  /// Verdadeiro quando não dá para afirmar se o servidor ficou com o pedido.
  ///
  /// Cobre tempo esgotado, falha de transporte em que o body pode ter saído,
  /// corpo ilegível que não seja 409 ou 500 com chave enviada, 404
  /// `NOT_FOUND`, 4xx não reconhecido depois da chave, resposta 2xx que não
  /// pôde ser lida como [Order] e HTTP 5xx que não prova a ausência do pedido.
  /// Não é falha definitiva e não autoriza outra chave. HTTP 401
  /// `UNAUTHORIZED` não entra aqui: a API atual recusa o acesso antes de
  /// processar o pedido.
  final bool outcomeUncertain;

  /// Verdadeiro quando outro POST, com esta chave ou com uma chave nova, é inseguro.
  final bool resendBlocked;

  /// A falha não criou o pedido, mas a chave e o payload continuam válidos.
  ///
  /// Usado no HTTP 401 `UNAUTHORIZED`. Não libera outra chave e não pede
  /// limpeza do carrinho.
  final bool retainsIntent;

  /// A futura tela do carrinho limpa os itens somente neste caso.
  bool get shouldClearCart => order != null;
}

/// Resultado de `PATCH /orders/:id/status`, já traduzido para o ViewModel.
class OrderUpdate {
  OrderUpdate.ready(Order order) : this._(order: order);

  const OrderUpdate.unavailable(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
  }) : this._(message: message, failure: failure, detail: detail);

  const OrderUpdate._({this.order, this.message, this.failure, this.detail});

  /// `null` quando o avanço falhou.
  final Order? order;

  /// Preenchida só quando o avanço falha.
  final String? message;

  /// Nula quando o pedido atualizou.
  final DataFailure? failure;

  /// Causa técnica. A tela usa [message].
  final String? detail;
}

/// Body e validação local de `POST /orders`, compartilhados pelo envio.
///
/// A validação acontece antes de gravar a intenção. O body congelado é o que
/// segue em toda tentativa da mesma chave. `note` nula fica de fora; `note`
/// vazia permanece.
abstract final class OrderRequest {
  static const emptyTableMessage = 'Informe a mesa';

  static const emptyItemsMessage = 'O pedido precisa de ao menos um item';

  static const invalidItemMessage = 'Item do pedido inválido';

  static OrderSubmission? rejection({required String table, required List<CartItem> items}) {
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

  static List<Map<String, Object?>> itemMaps(List<CartItem> items) => [
    for (final item in items) item.toOrderItem().toJson(),
  ];

  static Map<String, Object?> body({required String table, required List<CartItem> items}) => {
    'table': table,
    'items': <Object?>[...itemMaps(items)],
  };
}

/// Pedido consultado, ou a falha já traduzida. Não carrega status HTTP.
final class OrderLookup {
  OrderLookup.ready(Order order) : this._(order: order);

  const OrderLookup.unavailable(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
  }) : this._(message: message, failure: failure, detail: detail);

  const OrderLookup._({this.order, this.message, this.failure, this.detail});

  /// `null` quando a consulta falhou.
  final Order? order;

  /// Preenchida só quando a consulta falha.
  final String? message;

  /// Nula quando o pedido foi lido.
  final DataFailure? failure;

  /// Causa técnica. Quem consulta o número não transforma isso em falha de envio.
  final String? detail;
}

/// Fonte dos pedidos.
///
/// [list] traduz `GET /orders` na ordem recebida; o ViewModel da fila ordena.
/// [findById] traduz `GET /orders/:id` e não cria pedido.
/// [create] traduz `POST /orders`. O body é mesa e itens.
/// [updateStatus] traduz `PATCH /orders/:id/status`. O total não é calculado aqui.
abstract interface class OrderRepository {
  Future<OrderList> list();

  /// Lê um pedido existente. Identificador vazio não chama a API.
  Future<OrderLookup> findById(String id);

  /// Cria o pedido da mesa.
  ///
  /// [items] são os [CartItem] do carrinho. Mesa vazia, lista vazia,
  /// identificador em branco ou quantidade inválida voltam como
  /// [DataFailure.validation], sem chamar a API.
  ///
  /// [idempotencyKey] e [body], quando presentes, identificam uma intenção já
  /// gravada. [body] é enviado como está. Sem os dois, o POST segue o contrato
  /// anterior e cada chamada pode criar um pedido.
  Future<OrderSubmission> create({
    required String table,
    required List<CartItem> items,
    String? idempotencyKey,
    Map<String, Object?>? body,
  });

  /// Avança o pedido para [status]. O body envia o status destino.
  Future<OrderUpdate> updateStatus({required String id, required OrderStatus status});
}
