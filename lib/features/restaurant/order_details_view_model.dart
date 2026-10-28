import 'package:flutter/foundation.dart';

import '../../core/domain/order.dart';
import '../../core/domain/order_item.dart';
import '../../core/domain/order_status.dart';
import '../menu/product_repository.dart';

/// Linha do detalhe: quantidade e observação vêm do pedido; o nome, do cardápio.
final class OrderDetailItem {
  const OrderDetailItem({required this.quantity, required this.name, required this.note});

  final int quantity;
  final String name;
  final String? note;
}

/// Detalhe do pedido: ViewModel → [ProductRepository]. Não conhece HTTP.
///
/// O [Order] chega da fila. Este ViewModel só consulta `GET /products` uma vez
/// para resolver os nomes. Falha ou produto ausente não apaga mesa, itens,
/// quantidades, observações, horário, status nem total.
///
/// Depois do [dispose], a resposta pendente não altera estado nem notifica.
class OrderDetailsViewModel extends ChangeNotifier {
  OrderDetailsViewModel(this._products, {required this.order});

  final ProductRepository _products;
  final Order order;

  /// Nome enquanto o cardápio ainda não respondeu.
  static const pendingProductName = '…';

  /// O cardápio carregou e este `productId` não está na lista.
  static const missingProductName = 'Produto não encontrado';

  /// A consulta ao cardápio falhou. O pedido continua visível.
  static const unavailableProductName = 'Nome indisponível';

  /// Mensagem quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedCatalogMessage = 'Não foi possível carregar os nomes dos produtos';

  bool _resolving = false;
  bool _settled = false;
  bool _failed = false;
  bool _requested = false;
  bool _disposed = false;
  String? _productLookupMessage;
  Map<String, String> _names = const {};

  String get table => order.table;

  OrderStatus get status => order.status;

  DateTime get createdAt => order.createdAt;

  int get totalCents => order.totalCents;

  /// Consulta do cardápio em andamento. O pedido já pode ser exibido.
  bool get isResolvingProducts => _resolving;

  /// Preenchida só quando a consulta ao cardápio falha.
  String? get productLookupMessage => _productLookupMessage;

  List<OrderDetailItem> get items => [for (final item in order.items) _present(item)];

  /// Uma consulta por instância. Uma segunda chamada não dispara outra.
  Future<void> resolveProducts() async {
    if (_disposed || _requested) return;
    _requested = true;
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
      for (final product in products) {
        names[product.id] = product.name;
      }
      _names = Map.unmodifiable(names);
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
            library: 'order details view model',
            context: ErrorDescription('ao resolver os nomes dos produtos'),
          ),
        );
      }
    }
  }

  OrderDetailItem _present(OrderItem item) {
    final note = item.note;
    final visibleNote = note == null || note.trim().isEmpty ? null : note;
    return OrderDetailItem(
      quantity: item.quantity,
      name: _nameFor(item.productId),
      note: visibleNote,
    );
  }

  String _nameFor(String productId) {
    if (!_settled) return pendingProductName;
    final name = _names[productId];
    if (name != null) return name;
    if (_failed) return unavailableProductName;
    return missingProductName;
  }

  void _fail(String? message) {
    _names = const {};
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
