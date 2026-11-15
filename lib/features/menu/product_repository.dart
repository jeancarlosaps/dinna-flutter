import '../../core/domain/data_failure.dart';
import '../../core/domain/product.dart';

/// Cardápio já traduzido para o ViewModel.
///
/// Não carrega status HTTP nem exceção de transporte. Lista vazia é sucesso:
/// [products] vem vazio e [message] fica nula. Falha deixa [products] nulo.
/// [failure] classifica essa falha para a apresentação.
class ProductList {
  ProductList.ready(List<Product> products) : this._(products: List.unmodifiable(products));

  const ProductList.unavailable(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
  }) : this._(message: message, failure: failure, detail: detail);

  const ProductList._({this.products, this.message, this.failure, this.detail});

  /// `null` quando a listagem falhou. Lista vazia significa cardápio sem itens.
  final List<Product>? products;

  /// Preenchida só quando a listagem falha.
  final String? message;

  /// Nula quando a lista carregou.
  final DataFailure? failure;

  /// Causa técnica. A tela usa [message].
  final String? detail;
}

/// Produto já traduzido para o ViewModel.
///
/// Não carrega status HTTP nem exceção de transporte. Sucesso traz [product].
/// Falha deixa [product] nulo. [failure] classifica essa falha para a tela.
class ProductDetail {
  ProductDetail.ready(Product product) : this._(product: product);

  const ProductDetail.unavailable(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
  }) : this._(message: message, failure: failure, detail: detail);

  const ProductDetail._({this.product, this.message, this.failure, this.detail});

  /// `null` quando a consulta falhou.
  final Product? product;

  /// Preenchida só quando a consulta falha.
  final String? message;

  /// Nula quando o produto carregou.
  final DataFailure? failure;

  /// Causa técnica. A tela usa [message].
  final String? detail;
}

/// Fonte dos produtos do cardápio.
///
/// [list] traduz `GET /products`. [findById] traduz `GET /products/:id`.
/// [create] traduz `POST /products` e [update] traduz `PUT /products/:id`.
/// [deactivate] traduz `DELETE /products/:id`, que só marca `available: false`.
/// O ViewModel depende deste contrato e não vê HTTP.
///
/// A API também aceita `category`, `q` e `available` na query de [list].
/// Este contrato pede a lista inteira; o filtro entra quando a tela precisar.
abstract interface class ProductRepository {
  Future<ProductList> list();

  /// Produto completo do contrato, ou falha traduzida.
  ///
  /// `available: false` ainda é sucesso: o produto existe e a tela decide o
  /// que mostrar. Id inexistente chega como [DataFailure.notFound].
  Future<ProductDetail> findById(String id);

  /// Cria o produto. O `id` vem na resposta `201`.
  Future<ProductSave> create(ProductInput input);

  /// Substitui os campos editáveis. `id` vazio não chama a API.
  Future<ProductSave> update({required String id, required ProductInput input});

  /// Soft-delete. Sucesso não traz corpo; repetir a chamada continua sucesso.
  Future<ProductSave> deactivate(String id);
}

/// Produto gravado, desativado, ou a falha já traduzida.
final class ProductSave {
  ProductSave.saved(Product product) : this._(product: product);

  const ProductSave.removed() : this._(removed: true);

  const ProductSave.failed(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
  }) : this._(message: message, failure: failure, detail: detail);

  const ProductSave._({
    this.product,
    this.removed = false,
    this.message,
    this.failure,
    this.detail,
  });

  /// Preenchido só quando a criação ou a edição confirmou o produto.
  final Product? product;

  /// Verdadeiro só no soft-delete confirmado.
  final bool removed;

  /// Preenchida só quando a operação falha.
  final String? message;

  /// Nula quando a operação confirmou.
  final DataFailure? failure;

  /// Causa técnica. A tela usa [message].
  final String? detail;
}
