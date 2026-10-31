import '../../core/domain/cart_item.dart';
import '../../core/domain/data_failure.dart';
import '../../core/domain/order.dart';

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
  }) : this._(
         message: message,
         failure: failure,
         detail: detail,
         outcomeUncertain: outcomeUncertain,
       );

  const OrderSubmission._({
    this.order,
    this.message,
    this.failure,
    this.detail,
    this.outcomeUncertain = false,
  });

  /// Texto quando o POST pode ter sido aplicado e a confirmação não chegou.
  ///
  /// Não afirma que o pedido falhou. A mesma frase está em
  /// `ApiClient.uncertainOutcomeMessage`; o client não importa esta feature.
  static const uncertainOutcomeMessage =
      'Não foi possível confirmar o envio. O pedido pode ter sido registrado.';

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
  /// Cobre tempo esgotado, falha de transporte em que o body pode ter saído
  /// e resposta 2xx que não pôde ser lida como [Order]. Não é falha definitiva.
  final bool outcomeUncertain;

  /// A futura tela do carrinho limpa os itens somente neste caso.
  bool get shouldClearCart => order != null;
}

/// Fonte dos pedidos.
///
/// [list] traduz `GET /orders` na ordem recebida; o ViewModel da fila ordena.
/// [create] traduz `POST /orders`. O body é mesa e itens. O total não é
/// calculado aqui.
abstract interface class OrderRepository {
  Future<OrderList> list();

  /// Cria o pedido da mesa.
  ///
  /// [items] são os [CartItem] do carrinho. Mesa vazia, lista vazia,
  /// identificador em branco ou quantidade inválida voltam como
  /// [DataFailure.validation], sem chamar a API.
  Future<OrderSubmission> create({required String table, required List<CartItem> items});
}
