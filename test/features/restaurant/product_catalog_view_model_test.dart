import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/product_catalog_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';

void main() {
  test('32,90 e 32.90 e 32 viram centavos', () {
    expect(tryParsePriceCents('32,90'), 3290);
    expect(tryParsePriceCents('R\$ 32.90'), 3290);
    expect(tryParsePriceCents('1.890,50'), 189050);
    expect(tryParsePriceCents('18'), 1800);
    expect(tryParsePriceCents(''), isNull);
    expect(tryParsePriceCents('32,900'), isNull);
    expect(formatPriceInput(3290), '32,90');
  });

  test('lista os produtos, inclusive os esgotados', () async {
    final available = sampleProduct(id: 'p1', name: 'Burger');
    final gone = sampleProduct(id: 'p8', name: 'Veggie', available: false);
    final repository = FakeProductRepository(() async => ProductList.ready([available, gone]));
    final viewModel = ProductCatalogViewModel(repository);
    addTearDown(viewModel.dispose);

    await viewModel.load();

    expect(viewModel.status, ProductCatalogStatus.ready);
    expect(viewModel.products.map((product) => product.id), ['p1', 'p8']);
    expect(viewModel.isEmpty, isFalse);
  });

  test('cadastro envia o body mínimo e entra na lista', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready(const []),
      onCreate: (input) async => ProductSave.saved(
        Product(
          id: 'p_novo',
          name: input.name,
          description: input.description,
          category: input.category,
          priceCents: input.priceCents,
          imageUrl: input.imageUrl,
          available: input.available,
          ingredients: input.ingredients,
        ),
      ),
    );
    final viewModel = ProductCatalogViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.load();

    final message = await viewModel.save(
      name: ' Milkshake ',
      description: 'Creme de baunilha',
      category: 'bebidas',
      priceText: '18,90',
      imageText: '',
      ingredientsText: '',
      available: true,
    );

    expect(message, isNull);
    expect(repository.createCalls, 1);
    expect(repository.lastInput?.toJson(), {
      'name': 'Milkshake',
      'description': 'Creme de baunilha',
      'category': 'bebidas',
      'priceCents': 1890,
      'imageUrl': null,
      'available': true,
      'ingredients': <String>[],
    });
    expect(viewModel.products.single.id, 'p_novo');
    expect(viewModel.products.single.name, 'Milkshake');
  });

  test('preço inválido não chama a API', () async {
    final repository = FakeProductRepository(() async => ProductList.ready(const []));
    final viewModel = ProductCatalogViewModel(repository);
    addTearDown(viewModel.dispose);

    final message = await viewModel.save(
      name: 'Milkshake',
      description: '',
      category: 'bebidas',
      priceText: 'caro',
      imageText: '',
      ingredientsText: '',
      available: true,
    );

    expect(message, ProductCatalogViewModel.priceError);
    expect(repository.createCalls, 0);
  });

  test('400 da API volta como texto e não entra na lista', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready(const []),
      onCreate: (_) async =>
          const ProductSave.failed('Nome inválido', failure: DataFailure.validation),
    );
    final viewModel = ProductCatalogViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.load();

    final message = await viewModel.save(
      name: 'Milkshake',
      description: '',
      category: 'bebidas',
      priceText: '18,90',
      imageText: '',
      ingredientsText: '',
      available: true,
    );

    expect(message, 'Nome inválido');
    expect(viewModel.isEmpty, isTrue);
  });

  test('desativar marca o produto como esgotado', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger')]),
      onDeactivate: (_) async => const ProductSave.removed(),
    );
    final viewModel = ProductCatalogViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.load();

    final message = await viewModel.deactivate('p1');

    expect(message, isNull);
    expect(repository.deactivateCalls, 1);
    expect(viewModel.products.single.available, isFalse);
  });
}
