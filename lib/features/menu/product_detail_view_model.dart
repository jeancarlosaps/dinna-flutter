import 'package:flutter/foundation.dart';

import '../../core/domain/data_failure.dart';
import '../../core/domain/product.dart';
import 'product_repository.dart';

/// Estado do detalhe para a View. Ela não lê HTTP.
enum ProductDetailStatus { idle, loading, ready, failed }

/// Detalhe de um produto: ViewModel → [ProductRepository.findById].
///
/// Não conhece rota, ingredientes nem carrinho. A tela observa [status],
/// [product], [errorMessage] e [failure].
///
/// [DataFailure.notFound] é produto inexistente. Rede, tempo esgotado e as
/// demais falhas ficam em [DataFailure.unavailable]. `available: false` é
/// [ProductDetailStatus.ready]: o produto existe.
///
/// Depois do [dispose], a resposta pendente não altera estado nem notifica.
class ProductDetailViewModel extends ChangeNotifier {
  ProductDetailViewModel(this._repository, {required this.productId});

  final ProductRepository _repository;

  /// Id pedido em `GET /products/:id`.
  final String productId;

  /// Mensagem quando o repository deixa escapar uma falha que não traduziu.
  static const unexpectedFailureMessage = 'Não foi possível carregar o produto';

  ProductDetailStatus _status = ProductDetailStatus.idle;
  Product? _product;
  String? _errorMessage;
  DataFailure? _failure;
  bool _disposed = false;

  ProductDetailStatus get status => _status;

  /// Preenchido só em [ProductDetailStatus.ready].
  Product? get product => _product;

  /// Preenchida só quando a consulta falha.
  String? get errorMessage => _errorMessage;

  /// Nula enquanto não houve falha.
  DataFailure? get failure => _failure;

  bool get isLoading => _status == ProductDetailStatus.loading;

  /// Uma consulta por vez. Uma chamada durante o loading é ignorada.
  ///
  /// Depois de sucesso ou falha, uma nova chamada busca de novo.
  Future<void> load() async {
    if (_disposed || _status == ProductDetailStatus.loading) return;

    _status = ProductDetailStatus.loading;
    _product = null;
    _errorMessage = null;
    _failure = null;
    _notify();

    try {
      final result = await _repository.findById(productId);
      if (_disposed) return;
      final product = result.product;
      if (product == null) {
        _publish(
          status: ProductDetailStatus.failed,
          message: _visibleMessage(result.message),
          failure: result.failure ?? DataFailure.unavailable,
        );
        return;
      }
      _publish(status: ProductDetailStatus.ready, product: product);
    } catch (error, stackTrace) {
      if (_disposed) return;
      _publish(
        status: ProductDetailStatus.failed,
        message: unexpectedFailureMessage,
        failure: DataFailure.unavailable,
      );
      if (kDebugMode) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'product detail view model',
            context: ErrorDescription('ao carregar o produto'),
          ),
        );
      }
    }
  }

  String _visibleMessage(String? message) {
    if (message == null || message.trim().isEmpty) return unexpectedFailureMessage;
    return message;
  }

  void _publish({
    required ProductDetailStatus status,
    Product? product,
    String? message,
    DataFailure? failure,
  }) {
    if (_disposed) return;
    _status = status;
    _product = product;
    _errorMessage = message;
    _failure = failure;
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
