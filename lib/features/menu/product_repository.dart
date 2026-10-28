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

/// Fonte da lista de produtos do cardápio.
///
/// A implementação concreta traduz o JSON de `GET /products` e as falhas de
/// transporte para [ProductList]. O ViewModel depende deste contrato.
///
/// A API também aceita `category`, `q` e `available` na query. Este contrato
/// pede a lista inteira; o filtro entra quando a tela precisar.
abstract interface class ProductRepository {
  Future<ProductList> list();
}
