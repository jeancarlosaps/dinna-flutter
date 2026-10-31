import 'package:flutter/foundation.dart';

import '../../../core/domain/cart_item.dart';
import '../../menu/product_repository.dart';
import 'cart_lines.dart';

/// Linha já pronta para a tela: quantidade local, nome e preço do cardápio.
final class CartRow {
  const CartRow({
    required this.quantity,
    required this.name,
    required this.note,
    required this.lineTotalCents,
  });

  final int quantity;
  final String name;
  final String? note;

  /// Preço da linha em centavos. Nulo enquanto o cardápio não precificou.
  final int? lineTotalCents;
}

/// Revisão das linhas recebidas. Não envia pedido e não grava em disco.
///
/// A identidade da linha é a posição em [CartLines]. Duas linhas com o mesmo
/// produto e a mesma observação são alteradas em separado. [CartItem] ainda
/// não tem `lineId`; [_withQuantity] é o único lugar que copia a linha, e
/// precisa repassar esse campo quando ele existir.
///
/// Depois do [dispose], resposta pendente não altera estado nem notifica.
class CartViewModel extends ChangeNotifier {
  CartViewModel(ProductRepository products, {required CartLines lines})
    : this._(products, lines, List<CartItem>.of(lines.read()));

  CartViewModel._(this._products, this._lines, List<CartItem> initial)
    : _committed = List<CartItem>.of(initial),
      _items = List<CartItem>.of(initial);

  final ProductRepository _products;
  final CartLines _lines;
  final List<CartItem> _committed;
  final List<CartItem> _items;

  /// Nome enquanto o cardápio ainda não respondeu.
  static const pendingProductName = '…';

  /// O cardápio carregou e este `productId` não está na lista.
  static const missingProductName = 'Produto não encontrado';

  /// A consulta ao cardápio falhou. A linha continua no carrinho.
  static const unavailableProductName = 'Nome indisponível';

  /// Mensagem quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedCatalogMessage = 'Não foi possível carregar os preços dos produtos';

  bool _resolving = false;
  bool _settled = false;
  bool _failed = false;
  bool _requested = false;
  bool _disposed = false;
  String? _productLookupMessage;
  Map<String, String> _names = const {};
  Map<String, int> _prices = const {};

  bool get isResolvingProducts => _resolving;

  /// Preenchida só quando a consulta ao cardápio falha.
  String? get productLookupMessage => _productLookupMessage;

  /// Soma `priceCents * quantity`. Nula se o cardápio falhou ou falta preço.
  ///
  /// Este valor é estimado. O total confirmado do pedido continua sendo
  /// `order.totalCents`, calculado no servidor.
  int? get estimatedTotalCents {
    if (!_settled || _failed || _items.isEmpty) return null;
    var total = 0;
    for (final item in _items) {
      final price = _prices[item.productId];
      if (price == null) return null;
      total += price * item.quantity;
    }
    return total;
  }

  List<CartRow> get rows => [for (final item in _items) _present(item)];

  /// Uma consulta por instância. Carrinho vazio não chama o cardápio.
  Future<void> resolveProducts() async {
    if (_disposed || _requested) return;
    _requested = true;
    if (_items.isEmpty) {
      _settled = true;
      return;
    }
    _resolving = true;
    _notify();

    try {
      final result = await _products.list();
      if (_disposed) return;
      final products = result.products;
      if (products == null) {
        _fail(result.message);
        return;
      }
      final names = <String, String>{};
      final prices = <String, int>{};
      for (final product in products) {
        names[product.id] = product.name;
        prices[product.id] = product.priceCents;
      }
      _names = Map.unmodifiable(names);
      _prices = Map.unmodifiable(prices);
      _failed = false;
      _productLookupMessage = null;
      _resolving = false;
      _settled = true;
      _notify();
    } catch (error, stackTrace) {
      if (_disposed) return;
      _fail(unexpectedCatalogMessage);
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'cart view model',
            context: ErrorDescription('ao resolver os preços dos produtos'),
          ),
        );
      }
    }
  }

  void increase(int index) {
    if (_disposed || !_contains(index)) return;
    final current = _items[index];
    _items[index] = _withQuantity(current, current.quantity + 1);
    _publish();
  }

  /// Quantidade 1 permanece. A saída da linha é [removeAt].
  void decrease(int index) {
    if (_disposed || !_contains(index)) return;
    final current = _items[index];
    if (current.quantity <= 1) return;
    _items[index] = _withQuantity(current, current.quantity - 1);
    _publish();
  }

  void removeAt(int index) {
    if (_disposed || !_contains(index)) return;
    _items.removeAt(index);
    _publish();
  }

  bool _contains(int index) => index >= 0 && index < _items.length;

  CartRow _present(CartItem item) {
    final note = item.note;
    final visibleNote = note == null || note.trim().isEmpty ? null : note;
    return CartRow(
      quantity: item.quantity,
      name: _nameFor(item.productId),
      note: visibleNote,
      lineTotalCents: _lineTotal(item),
    );
  }

  int? _lineTotal(CartItem item) {
    if (!_settled || _failed) return null;
    final price = _prices[item.productId];
    if (price == null) return null;
    return price * item.quantity;
  }

  String _nameFor(String productId) {
    if (!_settled) return pendingProductName;
    final name = _names[productId];
    if (name != null) return name;
    if (_failed) return unavailableProductName;
    return missingProductName;
  }

  void _publish() {
    if (_disposed) return;
    final next = List<CartItem>.of(_items);
    if (!_lines.replace(_committed, next)) {
      final external = _lines.read();
      _items
        ..clear()
        ..addAll(external);
      _committed
        ..clear()
        ..addAll(external);
      _notify();
      return;
    }
    _committed
      ..clear()
      ..addAll(next);
    _notify();
  }

  void _fail(String? message) {
    _names = const {};
    _prices = const {};
    _failed = true;
    _resolving = false;
    _settled = true;
    _productLookupMessage = message == null || message.isEmpty ? unexpectedCatalogMessage : message;
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

/// Copia a linha com outra quantidade.
///
/// Hoje o model só tem `productId`, `quantity` e `note`. Quando `lineId`
/// entrar em [CartItem], o novo campo precisa ser copiado aqui. Sem essa
/// cópia, trocar a quantidade perde a identidade da linha.
CartItem _withQuantity(CartItem item, int quantity) {
  return CartItem(productId: item.productId, quantity: quantity, note: item.note);
}
