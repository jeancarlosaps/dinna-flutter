import '../../../core/domain/cart_item.dart';

/// Persistência local das linhas do carrinho.
///
/// Cada inclusão cria uma linha com identidade estável. Atualizações e
/// remoções atuam nessa identidade, sem substituir uma fotografia antiga do
/// carrinho por cima do estado mais recente.
abstract interface class CartRepository {
  Future<List<CartItem>> load();

  /// Insere uma nova linha e devolve o item com seu [CartItem.lineId].
  Future<CartItem> add({required String productId, required int quantity, String? note});

  /// Atualiza quantidade e observação da linha identificada por [item.lineId].
  /// Devolve `false` quando a linha já não existe.
  Future<bool> update(CartItem item);

  /// Remove somente a linha identificada por [lineId].
  Future<bool> remove(String lineId);

  /// Reconcilia a fotografia confirmada pela API contra o carrinho atual.
  ///
  /// A implementação lê e altera o estado persistido na mesma transação,
  /// preservando linhas novas e edições feitas enquanto o pedido era enviado.
  /// Devolve o estado persistido resultante.
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems);
}
