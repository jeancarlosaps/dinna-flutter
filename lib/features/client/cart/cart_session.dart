import 'package:flutter/foundation.dart';

import '../../../core/domain/cart_item.dart';
import 'cart_repository.dart';

/// Sessão única do carrinho. O cache só publica operações confirmadas pelo
/// repositório, que mantém o SQLite como fonte persistida.
final class CartSession extends ChangeNotifier {
  CartSession(this._repository);

  final CartRepository _repository;
  List<CartItem> _items = const [];
  Future<void> _pendingOperations = Future<void>.value();
  bool _isReady = false;
  bool _isRestoring = false;
  bool _disposed = false;
  int _pendingCount = 0;
  Object? _restoreError;

  bool get isReady => _isReady;
  bool get isRestoring => _isRestoring;
  Object? get restoreError => _restoreError;

  /// Há operação na fila ainda sem resposta do repositório. Vale para qualquer
  /// tela, inclusive uma aberta depois de a operação começar.
  bool get hasPendingOperations => _pendingCount > 0;

  /// Linhas confirmadas, na mesma ordem devolvida pelo SQLite.
  List<CartItem> read() {
    if (!_isReady) throw StateError('O carrinho ainda não foi restaurado');
    return List<CartItem>.unmodifiable(_items);
  }

  /// Recupera o carrinho persistido. Uma falha não publica lista vazia.
  Future<void> restore() => _enqueue(() async {
    _checkNotDisposed();
    _isReady = false;
    _isRestoring = true;
    _restoreError = null;
    _notify();
    try {
      final loaded = await _repository.load();
      _items = List<CartItem>.unmodifiable(loaded);
      _isReady = true;
      _isRestoring = false;
      _notify();
    } catch (error) {
      _isReady = false;
      _isRestoring = false;
      _restoreError = error;
      _notify();
      rethrow;
    }
  });

  /// Persiste uma nova linha e publica o item com identidade gerada pelo repo.
  Future<CartItem> addLine({required String productId, required int quantity, String? note}) {
    return _enqueue(() async {
      _ensureReady();
      final added = await _repository.add(productId: productId, quantity: quantity, note: note);
      if (added.lineId == null) {
        throw StateError('O repositório não atribuiu identidade à linha do carrinho');
      }
      _items = List<CartItem>.unmodifiable([..._items, added]);
      _notify();
      return added;
    });
  }

  /// Persiste a edição da linha. `null` significa que a linha não foi atualizada;
  /// nesse caso o cache é substituído por uma leitura atual do repositório.
  Future<CartItem?> updateLine({required String lineId, required int quantity, String? note}) {
    return _enqueue(() async {
      _ensureReady();
      final index = _items.indexWhere((item) => item.lineId == lineId);
      if (index < 0) return null;

      final current = _items[index];
      final updated = CartItem(
        lineId: current.lineId,
        productId: current.productId,
        quantity: quantity,
        note: note,
      );
      if (!await _repository.update(updated)) {
        await _reload();
        return null;
      }

      final next = List<CartItem>.of(_items)..[index] = updated;
      _items = List<CartItem>.unmodifiable(next);
      _notify();
      return updated;
    });
  }

  /// Aplica uma variação sobre a quantidade mais recente, dentro da fila
  /// compartilhada da sessão. Isso evita perder incrementos concorrentes vindos
  /// de duas instâncias de tela/ViewModel.
  Future<CartItem?> changeQuantity({required String lineId, required int delta}) {
    return _enqueue(() async {
      _ensureReady();
      final index = _items.indexWhere((item) => item.lineId == lineId);
      if (index < 0) return null;

      final current = _items[index];
      final nextQuantity = current.quantity + delta;
      final updated = CartItem(
        lineId: current.lineId,
        productId: current.productId,
        quantity: nextQuantity < 1 ? 1 : nextQuantity,
        note: current.note,
      );
      if (updated.quantity == current.quantity) return current;
      if (!await _repository.update(updated)) {
        await _reload();
        return null;
      }

      final next = List<CartItem>.of(_items)..[index] = updated;
      _items = List<CartItem>.unmodifiable(next);
      _notify();
      return updated;
    });
  }

  /// Tira da sessão a fotografia que a API já confirmou.
  ///
  /// O repositório compara a linha atual e preserva quantidade extra, observação
  /// nova ou linha criada durante o envio. Uma falha não publica lista vazia.
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) {
    return _enqueue(() async {
      _ensureReady();
      final left = await _repository.removeConfirmed(confirmedItems);
      _items = List<CartItem>.unmodifiable(left);
      _notify();
      return _items;
    });
  }

  /// Aplica a conciliação durável e publica o carrinho que o banco devolveu.
  Future<CartReconciliationResult> reconcileConfirmed({
    required String intentId,
    required List<CartItem> confirmedItems,
  }) {
    return _enqueue(() async {
      _ensureReady();
      final result = await _repository.reconcileConfirmed(
        intentId: intentId,
        confirmedItems: confirmedItems,
      );
      _items = List<CartItem>.unmodifiable(result.items);
      _notify();
      return result;
    });
  }

  /// Remove a linha apenas depois da confirmação do repositório.
  Future<void> removeLine(String lineId) => _enqueue(() async {
    _ensureReady();
    if (!await _repository.remove(lineId)) {
      await _reload();
      throw StateError('A linha do carrinho não existe mais');
    }
    _items = List<CartItem>.unmodifiable(_items.where((item) => item.lineId != lineId));
    _notify();
  });

  /// Sem leitura do SQLite, o cache deixa de ser confiável: a sessão volta a
  /// exigir [restore], sem descartar as linhas confirmadas antes.
  Future<void> _reload() async {
    final List<CartItem> loaded;
    try {
      loaded = await _repository.load();
    } catch (error) {
      _isReady = false;
      _restoreError = error;
      _notify();
      rethrow;
    }
    _items = List<CartItem>.unmodifiable(loaded);
    _notify();
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    _pendingCount++;
    _notify();
    final result = _pendingOperations.then((_) => operation()).whenComplete(() {
      _pendingCount--;
      _notify();
    });
    _pendingOperations = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _ensureReady() {
    _checkNotDisposed();
    if (!_isReady) throw StateError('O carrinho ainda não foi restaurado');
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('A sessão do carrinho foi encerrada');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
