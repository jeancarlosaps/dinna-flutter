import '../../core/domain/product.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'product_repository.dart';

/// Repository concreto do `GET /products`, usando o [ApiClient] como Service.
class HttpProductRepository implements ProductRepository {
  HttpProductRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Mensagem estável para corpo JSON que não é a lista do contrato.
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
}
