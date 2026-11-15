import '../../../core/domain/cart_item.dart';

/// Resultado de [CartRepository.reconcileConfirmed].
enum CartReconciliation {
  /// A quantidade enviada saiu do carrinho e o marcador ficou na mesma transação.
  applied,

  /// Este pedido já tinha marcador. O carrinho não foi alterado de novo.
  alreadyApplied,

  /// Há item sem identidade local. Nada foi subtraído e nada foi marcado.
  unresolved,
}

/// Carrinho depois da tentativa de conciliação e o que ela fez.
final class CartReconciliationResult {
  const CartReconciliationResult({required this.items, required this.outcome});

  final List<CartItem> items;
  final CartReconciliation outcome;
}

/// Persistência local das linhas do carrinho.
///
/// Cada inclusão cria uma linha com identidade estável. Atualizações e
/// remoções atuam nessa identidade, sem substituir uma fotografia antiga do
/// carrinho por cima do estado mais recente.
abstract class CartRepository {
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

  /// Tira os itens confirmados uma única vez para [intentId].
  ///
  /// A implementação durável grava o marcador na mesma transação da quantidade.
  /// O padrão apenas delega a [removeConfirmed] e não é idempotente: o SQLite
  /// substitui este método.
  Future<CartReconciliationResult> reconcileConfirmed({
    required String intentId,
    required List<CartItem> confirmedItems,
  }) async {
    final items = await removeConfirmed(confirmedItems);
    return CartReconciliationResult(items: items, outcome: CartReconciliation.applied);
  }
}
