import '../../core/domain/data_failure.dart';
import '../../core/domain/product.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'product_repository.dart';

/// Repository concreto de `GET /products` e `GET /products/:id`.
///
/// Usa o [ApiClient] como Service. Não decide tela nem ingredientes.
class HttpProductRepository implements ProductRepository {
  HttpProductRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Mensagem estável para corpo JSON que não é o contrato do produto.
  static const unexpectedResponseMessage = 'Resposta inesperada da API';

  @override
  Future<ProductList> list() async {
    try {
      final body = await _apiClient.getJson('/products');
      if (body is! List) return const ProductList.unavailable(unexpectedResponseMessage);

      final products = <Product>[for (final item in body) Product.fromJson(item as Object?)];
      return ProductList.ready(products);
    } on ApiException catch (error) {
      return ProductList.unavailable(error.message, failure: error.failure, detail: error.detail);
    } on FormatException {
      return const ProductList.unavailable(unexpectedResponseMessage);
    }
  }

  @override
  Future<ProductDetail> findById(String id) async {
    if (id.isEmpty) {
      return const ProductDetail.unavailable(
        'Identificador do produto inválido',
        failure: DataFailure.validation,
      );
    }

    try {
      final body = await _apiClient.getJson('/products/${Uri.encodeComponent(id)}');
      return ProductDetail.ready(Product.fromJson(body));
    } on ApiException catch (error) {
      return ProductDetail.unavailable(error.message, failure: error.failure, detail: error.detail);
    } on FormatException {
      return const ProductDetail.unavailable(unexpectedResponseMessage);
    }
  }
}
