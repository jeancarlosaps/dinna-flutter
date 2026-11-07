import '../../core/domain/product.dart';
import '../menu/product_repository.dart';
import 'recommendation.dart';

/// Sugestão já cruzada com um produto real do cardápio.
///
/// Nome, preço e imagem vêm só de [product]. [reason] vem só da IA.
final class RecommendedProduct {
  const RecommendedProduct({required this.product, required this.reason});

  final Product product;
  final String reason;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecommendedProduct && other.product == product && other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(product, reason);

  @override
  String toString() => 'RecommendedProduct(${product.id}, $reason)';
}

/// Cruzamento entre as sugestões e `GET /products`.
///
/// [products] nulo é falha da consulta. Lista vazia é sucesso sem prato
/// válido: id ausente ou produto indisponível não vira card.
final class RecommendationCatalogLookup {
  RecommendationCatalogLookup.ready(List<RecommendedProduct> products)
    : this._(products: List.unmodifiable(products));

  const RecommendationCatalogLookup.failed() : this._();

  const RecommendationCatalogLookup._({this.products});

  final List<RecommendedProduct>? products;
}

/// Lê o cardápio uma vez e mantém a ordem das sugestões.
///
/// Não consulta `GET /products/:id` e não completa dado que o cadastro não tem.
class RecommendationCatalog {
  RecommendationCatalog(this._products);

  final ProductRepository _products;

  Future<RecommendationCatalogLookup> lookup(List<RecommendationSuggestion> suggestions) async {
    try {
      final result = await _products.list();
      final products = result.products;
      if (products == null) return const RecommendationCatalogLookup.failed();
      return RecommendationCatalogLookup.ready(_match(suggestions, products));
    } catch (_) {
      return const RecommendationCatalogLookup.failed();
    }
  }
}

/// Ignora id ausente e produto indisponível. Duplicata no cardápio fica com
/// o primeiro disponível; se nenhum está disponível, o id sai da lista.
List<RecommendedProduct> _match(
  List<RecommendationSuggestion> suggestions,
  List<Product> products,
) {
  final byId = <String, Product>{};
  for (final product in products) {
    final current = byId[product.id];
    if (current == null || (!current.available && product.available)) {
      byId[product.id] = product;
    }
  }

  final resolved = <RecommendedProduct>[];
  for (final suggestion in suggestions) {
    final product = byId[suggestion.productId];
    if (product == null || !product.available) continue;
    resolved.add(RecommendedProduct(product: product, reason: suggestion.reason));
  }
  return resolved;
}
