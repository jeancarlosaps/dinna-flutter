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

  /// POST sem confirmação: o produto pode ter sido gravado. Não há nova tentativa.
  static const uncertainCreateMessage =
      'Não foi possível confirmar o cadastro. O produto pode ter sido criado: '
      'confira a lista antes de tentar de novo.';

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

  @override
  Future<ProductSave> create(ProductInput input) async {
    // `postJson` marca como incerta a queda depois do envio e o 2xx ilegível.
    // `POST /products` não tem chave de idempotência: repetir pode duplicar.
    try {
      final body = await _apiClient.postJson('/products', input.toJson());
      return ProductSave.saved(Product.fromJson(body));
    } on ApiException catch (error) {
      if (error.outcomeUncertain) {
        return ProductSave.failed(
          uncertainCreateMessage,
          failure: DataFailure.uncertain,
          detail: error.detail ?? error.message,
        );
      }
      return ProductSave.failed(error.message, failure: error.failure, detail: error.detail);
    } on FormatException {
      // 201 chegou, mas fora do contrato: o produto existe.
      return const ProductSave.failed(
        uncertainCreateMessage,
        failure: DataFailure.uncertain,
        detail: unexpectedResponseMessage,
      );
    }
  }

  @override
  Future<ProductSave> update({required String id, required ProductInput input}) async {
    if (id.isEmpty) {
      return const ProductSave.failed(
        'Identificador do produto inválido',
        failure: DataFailure.validation,
      );
    }

    try {
      final body = await _apiClient.putJson('/products/${Uri.encodeComponent(id)}', input.toJson());
      return ProductSave.saved(Product.fromJson(body));
    } on ApiException catch (error) {
      return ProductSave.failed(error.message, failure: error.failure, detail: error.detail);
    } on FormatException {
      return const ProductSave.failed(unexpectedResponseMessage);
    }
  }

  @override
  Future<ProductSave> deactivate(String id) async {
    if (id.isEmpty) {
      return const ProductSave.failed(
        'Identificador do produto inválido',
        failure: DataFailure.validation,
      );
    }

    try {
      await _apiClient.delete('/products/${Uri.encodeComponent(id)}');
      return const ProductSave.removed();
    } on ApiException catch (error) {
      return ProductSave.failed(error.message, failure: error.failure, detail: error.detail);
    }
  }
}
