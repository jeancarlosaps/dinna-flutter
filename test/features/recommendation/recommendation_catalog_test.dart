import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:dinna/features/recommendation/recommendation_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';

void main() {
  test('preserva a ordem e o motivo e ignora id ausente ou indisponível', () async {
    final burger = _product('p1', name: 'Burger da casa', priceCents: 1890);
    final salad = _product('p2', name: 'Salada da casa', priceCents: 2200);
    final soldOut = _product('p3', name: 'Peixe grelhado', available: false);
    final unrelated = _product('p8', name: 'Brownie', priceCents: 900);
    final repository = FakeProductRepository(
      () async => ProductList.ready([soldOut, unrelated, salad, burger]),
    );
    final lookup = await RecommendationCatalog(repository).lookup([
      _suggestion('p2', 'Leve, Salgado'),
      _suggestion('p9', 'Não está no cardápio'),
      _suggestion('p3', 'Peixe, Salgado'),
      _suggestion('p1', 'Carne, Salgado'),
    ]);

    expect(repository.calls, 1);
    expect(repository.findCalls, 0);
    expect(lookup.products, [
      RecommendedProduct(product: salad, reason: 'Leve, Salgado'),
      RecommendedProduct(product: burger, reason: 'Carne, Salgado'),
    ]);
    expect(lookup.products!.map((item) => item.product.name), ['Salada da casa', 'Burger da casa']);
    expect(
      lookup.products!.map((item) => item.product.description),
      everyElement('Descrição interna'),
    );
    expect(lookup.products!.every((item) => item.product.imageUrl == null), isTrue);
  });

  test('cardápio sem prato válido devolve lista vazia e não inventa produto', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([_product('p3', name: 'Peixe grelhado', available: false)]),
    );

    final lookup = await RecommendationCatalog(repository)
        .lookup([_suggestion('p3', 'Peixe, Salgado'), _suggestion('p9', 'Fora do cadastro')]);

    expect(lookup.products, isEmpty);
    expect(lookup.products, isNotNull);
  });

  test('falha da consulta não vira prato, inclusive quando o repositório lança', () async {
    final unavailable = FakeProductRepository(
      () async => const ProductList.unavailable('timeout cru', detail: 'SocketException'),
    );
    final failed = await RecommendationCatalog(unavailable)
        .lookup([_suggestion('p1', 'Carne, Salgado')]);
    expect(failed.products, isNull);
    expect(unavailable.findCalls, 0);

    final exploding = FakeProductRepository(() async => throw StateError('boom'));
    final thrown = await RecommendationCatalog(exploding)
        .lookup([_suggestion('p1', 'Carne, Salgado')]);
    expect(thrown.products, isNull);
  });

  test('id repetido no cardápio usa o primeiro registro disponível', () async {
    final soldOut = _product('p1', name: 'Burger esgotado', available: false, priceCents: 100);
    final available = _product('p1', name: 'Burger da casa', priceCents: 1890);
    final later = _product('p1', name: 'Outro burger', priceCents: 3000);
    final repository = FakeProductRepository(
      () async => ProductList.ready([soldOut, available, later]),
    );

    final lookup = await RecommendationCatalog(repository)
        .lookup([_suggestion('p1', 'Carne, Salgado')]);

    expect(lookup.products, hasLength(1));
    expect(lookup.products!.single.product, same(available));
    expect(lookup.products!.single.reason, 'Carne, Salgado');
  });
}

Product _product(String id, {required String name, int priceCents = 1890, bool available = true}) {
  return Product(
    id: id,
    name: name,
    description: 'Descrição interna',
    category: 'burgers',
    priceCents: priceCents,
    imageUrl: null,
    available: available,
  );
}

RecommendationSuggestion _suggestion(String id, String reason) {
  return RecommendationSuggestion(productId: id, reason: reason);
}
