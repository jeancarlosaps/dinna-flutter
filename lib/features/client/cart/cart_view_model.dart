import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/domain/cart_item.dart';
import '../../menu/product_repository.dart';
import 'cart_lines.dart';
import 'cart_session.dart';

/// Linha já pronta para a tela: quantidade local, nome e preço do cardápio.
final class CartRow {
  const CartRow({
    required this.quantity,
    required this.name,
    required this.note,
    required this.lineTotalCents,
    this.isAvailable = true,
  });

  final int quantity;
  final String name;
  final String? note;

  /// Preço da linha em centavos. Nulo enquanto o cardápio não precificou.
  final int? lineTotalCents;
  final bool isAvailable;
}

/// Revisão das linhas recebidas. Não envia pedido e não grava em disco.
///
/// A tela lê [items] e entrega a lista ao envio. Esta classe não chama o
/// repositório de pedidos.
///
/// Em produção, as linhas vêm da [CartSession]; o modo [CartLines] permanece
/// para testes e fluxos em memória. Duas linhas iguais continuam independentes
/// pela identidade [CartItem.lineId].
///
/// Depois do [dispose], resposta pendente não altera estado nem notifica.
class CartViewModel extends ChangeNotifier {
  CartViewModel(ProductRepository products, {required CartLines lines})
    : _products = products,
      _lines = lines,
      _session = null,
      _items = List<CartItem>.of(lines.read()),
      _legacyCommitted = List<CartItem>.of(lines.read());

  CartViewModel.persisted(ProductRepository products, {required CartSession session})
    : _products = products,
      _lines = null,
      _session = session,
      _items = List<CartItem>.of(session.read()),
      _legacyCommitted = const [] {
    session.addListener(_onSessionChanged);
  }

  final ProductRepository _products;
  final CartLines? _lines;
  final CartSession? _session;
  final List<CartItem> _items;
  final List<CartItem> _legacyCommitted;

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
  bool _isMutating = false;
  String? _productLookupMessage;
  String? _cartWriteErrorMessage;
  Map<String, String> _names = const {};
  Map<String, int> _prices = const {};
  Map<String, bool> _availability = const {};

  bool get isResolvingProducts => _resolving;

  bool get isMutating => _isMutating;

  /// Preenchida quando uma alteração persistida falha.
  String? get cartWriteErrorMessage => _cartWriteErrorMessage;

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

  /// Soma estimada de uma fotografia, com os preços já resolvidos.
  ///
  /// Nula enquanto o cardápio não confirmou o preço de cada item.
  int? estimateFor(List<CartItem> items) {
    if (!_settled || _failed || items.isEmpty) return null;
    var total = 0;
    for (final item in items) {
      final price = _prices[item.productId];
      if (price == null) return null;
      total += price * item.quantity;
    }
    return total;
  }

  List<CartRow> get rows => [for (final item in _items) _present(item)];

  /// Linhas atuais. O envio fotografa esta lista no momento do toque.
  List<CartItem> get items => List<CartItem>.unmodifiable(_items);

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
      final availability = <String, bool>{};
      for (final product in products) {
        names[product.id] = product.name;
        prices[product.id] = product.priceCents;
        availability[product.id] = product.available;
      }
      _names = Map.unmodifiable(names);
      _prices = Map.unmodifiable(prices);
      _availability = Map.unmodifiable(availability);
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

  Future<void> increase(int index) {
    if (_disposed || _isMutating || !_contains(index)) return Future.value();
    final current = _items[index];
    return _changeQuantity(index, current, 1);
  }

  /// Quantidade 1 permanece. A saída da linha é [removeAt].
  Future<void> decrease(int index) {
    if (_disposed || _isMutating || !_contains(index)) return Future.value();
    final current = _items[index];
    if (_session == null && current.quantity <= 1) return Future.value();
    return _changeQuantity(index, current, -1);
  }

  Future<void> removeAt(int index) {
    if (_disposed || _isMutating || !_contains(index)) return Future.value();
    final session = _session;
    if (session == null) {
      _items.removeAt(index);
      _publishLegacy();
      return Future.value();
    }
    final lineId = _items[index].lineId;
    if (lineId == null) return _reportCartWriteFailure();
    return _persistMutation(() => session.removeLine(lineId));
  }

  Future<void> _changeQuantity(int index, CartItem current, int delta) {
    final session = _session;
    if (session == null) {
      _items[index] = _withQuantity(current, current.quantity + delta);
      _publishLegacy();
      return Future.value();
    }
    final lineId = current.lineId;
    if (lineId == null) return _reportCartWriteFailure();
    return _persistMutation(() async {
      final updated = await session.changeQuantity(lineId: lineId, delta: delta);
      if (updated == null) throw StateError('A linha do carrinho não existe mais');
    });
  }

  Future<void> _persistMutation(Future<void> Function() mutation) async {
    _isMutating = true;
    _cartWriteErrorMessage = null;
    _notify();
    try {
      await mutation();
    } catch (_) {
      _cartWriteErrorMessage = 'Não foi possível salvar a alteração do carrinho. Tente novamente.';
    } finally {
      _isMutating = false;
      _notify();
    }
  }

  Future<void> _reportCartWriteFailure() async {
    _cartWriteErrorMessage = 'A linha do carrinho não tem uma identidade persistida.';
    _notify();
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
      isAvailable: _availability[item.productId] ?? true,
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

  void _publishLegacy() {
    if (_disposed) return;
    final next = List<CartItem>.of(_items);
    final lines = _lines!;
    if (!lines.replace(_legacyCommitted, next)) {
      final external = lines.read();
      _items
        ..clear()
        ..addAll(external);
      _legacyCommitted
        ..clear()
        ..addAll(external);
      _notify();
      return;
    }
    _legacyCommitted
      ..clear()
      ..addAll(next);
    _notify();
  }

  void _onSessionChanged() {
    if (_disposed || _session?.isReady != true) return;
    final next = _session!.read();
    final oldProductIds = _items.map((item) => item.productId).toSet();
    final nextProductIds = next.map((item) => item.productId).toSet();
    final hasNewProducts = nextProductIds.any((productId) => !oldProductIds.contains(productId));
    _items
      ..clear()
      ..addAll(next);
    // `list()` returns the full catalog, so an in-flight lookup already covers
    // any cart changes that arrive before it completes.
    if (hasNewProducts && !_resolving) {
      _requested = false;
      _settled = next.isEmpty;
      _failed = false;
      _productLookupMessage = null;
      _names = const {};
      _prices = const {};
      _availability = const {};
    }
    _notify();
    if (hasNewProducts && next.isNotEmpty && !_resolving) {
      unawaited(resolveProducts());
    }
  }

  void _fail(String? message) {
    _names = const {};
    _prices = const {};
    _availability = const {};
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
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }
}

/// Copia a linha com outra quantidade, inclusive a identidade local.
CartItem _withQuantity(CartItem item, int quantity) {
  return CartItem(
    lineId: item.lineId,
    productId: item.productId,
    quantity: quantity,
    note: item.note,
  );
}
