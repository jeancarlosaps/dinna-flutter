import 'package:flutter/foundation.dart';

import '../../core/domain/data_failure.dart';
import '../../core/domain/order.dart';
import '../../core/domain/order_item.dart';
import '../../core/domain/order_status.dart';
import '../menu/product_repository.dart';
import 'order_format.dart';
import 'order_repository.dart';

/// Linha do detalhe: dados do pedido; nome preferencialmente vem no item da API.
final class OrderDetailItem {
  const OrderDetailItem({
    required this.quantity,
    required this.name,
    required this.note,
    this.lineTotalCents,
  });

  final int quantity;
  final String name;
  final String? note;
  final int? lineTotalCents;
}

/// Detalhe do pedido: ViewModel → [OrderRepository] (+ catálogo só como fallback).
///
/// O [Order] chega da fila. Quando `OrderItem.name` já veio no payload, o
/// detalhe não consulta o cardápio. Caso contrário, tenta `GET /products`
/// uma vez. Falha do cardápio não apaga mesa, itens, horário, status nem total.
///
/// Depois do [dispose], a resposta pendente não altera estado nem notifica.
class OrderDetailsViewModel extends ChangeNotifier {
  OrderDetailsViewModel(this._products, this._orders, {required this._order});

  final ProductRepository _products;
  final OrderRepository _orders;
  Order _order;

  /// Nome enquanto o cardápio ainda não respondeu e o item não trouxe `name`.
  static const pendingProductName = '…';

  /// O cardápio carregou e este `productId` não está na lista.
  static const missingProductName = 'Produto não encontrado';

  /// A consulta ao cardápio falhou. O pedido continua visível.
  static const unavailableProductName = 'Nome indisponível';

  /// Mensagem quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedCatalogMessage = 'Não foi possível carregar os nomes dos produtos';

  /// Mensagem quando o avanço falha sem texto utilizável.
  static const unexpectedAdvanceMessage = 'Não foi possível atualizar o status';

  /// Conflito de transição (ex.: outro device já avançou).
  static const staleStatusMessage = 'Status desatualizado. Recarregue a fila.';

  bool _resolving = false;
  bool _settled = false;
  bool _failed = false;
  bool _requested = false;
  bool _updating = false;
  bool _disposed = false;
  String? _productLookupMessage;
  DataFailure? _productLookupFailure;
  String? _actionError;
  DataFailure? _actionFailure;
  Map<String, String> _names = const {};

  Order get order => _order;

  String get table => _order.table;

  int? get orderNumber => _order.orderNumber;

  OrderStatus get status => _order.status;

  DateTime get createdAt => _order.createdAt;

  int get totalCents => _order.totalCents;

  /// Consulta do cardápio em andamento. O pedido já pode ser exibido.
  bool get isResolvingProducts => _resolving;

  /// Preenchida só quando a consulta ao cardápio falha e ainda faltam nomes.
  String? get productLookupMessage => _productLookupMessage;

  /// Classificação da falha do cardápio. Nula quando os nomes carregaram.
  DataFailure? get productLookupFailure => _productLookupFailure;

  /// PATCH de status em andamento.
  bool get isUpdating => _updating;

  /// Falha do último avanço. O status anterior permanece.
  String? get actionError => _actionError;

  /// Classificação da falha do avanço.
  DataFailure? get actionFailure => _actionFailure;

  /// Há próximo status válido para o botão de avanço.
  bool get canAdvance => _order.status.next != null;

  List<OrderDetailItem> get items => [for (final item in _order.items) _present(item)];

  bool get _allItemsNamed => _order.items.every((item) {
    final name = item.name?.trim();
    return name != null && name.isNotEmpty;
  });

  /// Uma consulta por instância. Pula o cardápio se todos os itens já têm nome.
  Future<void> resolveProducts() async {
    if (_disposed || _requested) return;
    _requested = true;

    if (_allItemsNamed) {
      _settled = true;
      _resolving = false;
      _failed = false;
      _productLookupMessage = null;
      _productLookupFailure = null;
      _notify();
      return;
    }

    _resolving = true;
    _productLookupFailure = null;
    _notify();

    try {
      final result = await _products.list();
      if (_disposed) return;
      final products = result.products;
      if (products == null) {
        _fail(result.message, result.failure ?? DataFailure.unavailable);
        return;
      }
      final names = <String, String>{};
      for (final product in products) {
        names[product.id] = product.name;
      }
      _names = Map.unmodifiable(names);
      _failed = false;
      _productLookupMessage = null;
      _productLookupFailure = null;
      _resolving = false;
      _settled = true;
      _notify();
    } catch (error, stackTrace) {
      if (_disposed) return;
      _fail(unexpectedCatalogMessage, DataFailure.unavailable);
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'order details view model',
            context: ErrorDescription('ao resolver os nomes dos produtos'),
          ),
        );
      }
    }
  }

  void clearActionError() {
    if (_disposed || (_actionError == null && _actionFailure == null)) return;
    _actionError = null;
    _actionFailure = null;
    _notify();
  }

  /// Avança um passo o status. Ignora se já terminou ou se há PATCH em voo.
  Future<void> advanceStatus() async {
    final next = _order.status.next;
    if (_disposed || _updating || next == null) return;

    _updating = true;
    _actionError = null;
    _actionFailure = null;
    _notify();

    try {
      final result = await _orders.updateStatus(id: _order.id, status: next);
      if (_disposed) return;
      final updated = result.order;
      if (updated != null) {
        _order = updated.preservingItemSnapshotsFrom(_order);
        _actionError = null;
        _actionFailure = null;
        return;
      }
      final message = result.message;
      final failure = result.failure ?? DataFailure.unavailable;
      _actionError = failure == DataFailure.conflict
          ? staleStatusMessage
          : (message == null || message.isEmpty ? unexpectedAdvanceMessage : message);
      _actionFailure = failure;
    } catch (error, stackTrace) {
      if (_disposed) return;
      _actionError = unexpectedAdvanceMessage;
      _actionFailure = DataFailure.unavailable;
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'order details view model',
            context: ErrorDescription('ao avançar o status do pedido'),
          ),
        );
      }
    } finally {
      if (!_disposed) {
        _updating = false;
        _notify();
      }
    }
  }

  OrderDetailItem _present(OrderItem item) {
    return OrderDetailItem(
      quantity: item.quantity,
      name: _nameFor(item),
      note: orderItemNote(item.note),
      lineTotalCents: item.lineTotalCents,
    );
  }

  String _nameFor(OrderItem item) {
    final embedded = item.name?.trim();
    if (embedded != null && embedded.isNotEmpty) return embedded;
    if (!_settled) return pendingProductName;
    final name = _names[item.productId];
    if (name != null) return name;
    if (_failed) return unavailableProductName;
    return missingProductName;
  }

  void _fail(String? message, DataFailure failure) {
    _names = const {};
    _failed = true;
    _resolving = false;
    _settled = true;
    final needsBanner = _order.items.any((item) {
      final name = item.name?.trim();
      return name == null || name.isEmpty;
    });
    if (needsBanner) {
      _productLookupMessage = message == null || message.isEmpty
          ? unexpectedCatalogMessage
          : message;
      _productLookupFailure = failure;
    } else {
      _productLookupMessage = null;
      _productLookupFailure = null;
    }
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
