import 'dart:async';

import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/menu_view_model.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_product_repository.dart';

Product _product(String id, String category) => Product(
  id: id,
  name: 'Produto $id',
  description: '',
  category: category,
  priceCents: 1000,
  imageUrl: null,
  available: true,
);

void main() {
  test('carrega o cardápio e lista as categorias sem repetir', () async {
    final viewModel = MenuViewModel(
      FakeProductRepository(
        () async => ProductList.ready([
          _product('1', 'Pizzas'),
          _product('2', 'Saladas'),
          _product('3', 'Pizzas'),
        ]),
      ),
    );

    await viewModel.load();

    expect(viewModel.status, MenuStatus.ready);
    expect(viewModel.categories, ['Pizzas', 'Saladas']);
    expect(viewModel.visibleProducts, hasLength(3));
    expect(viewModel.productsIn('Pizzas').map((p) => p.id), ['1', '3']);
    final grouped = viewModel.groupedProducts();
    expect(grouped.keys, ['Pizzas', 'Saladas']);
    expect(grouped['Pizzas']!.map((p) => p.id), ['1', '3']);
    expect(grouped['Saladas']!.map((p) => p.id), ['2']);
    expect(grouped.values.fold<int>(0, (total, items) => total + items.length), 3);
  });

  test('filtra pela categoria escolhida e volta para todos', () async {
    final viewModel = MenuViewModel(
      FakeProductRepository(
        () async => ProductList.ready([_product('1', 'Pizzas'), _product('2', 'Saladas')]),
      ),
    );
    await viewModel.load();

    viewModel.selectCategory('Saladas');
    expect(viewModel.visibleProducts.map((p) => p.id), ['2']);

    viewModel.selectCategory(null);
    expect(viewModel.visibleProducts, hasLength(2));
  });

  test('falha mostra a mensagem do repository', () async {
    final viewModel = MenuViewModel(
      FakeProductRepository(() async => const ProductList.unavailable('Sem conexão')),
    );

    await viewModel.load();

    expect(viewModel.status, MenuStatus.failed);
    expect(viewModel.errorMessage, 'Sem conexão');
  });

  test('resposta antiga não cobre a carga mais nova', () async {
    final first = Completer<ProductList>();
    final second = Completer<ProductList>();
    var calls = 0;
    final viewModel = MenuViewModel(
      FakeProductRepository(() {
        calls += 1;
        return calls == 1 ? first.future : second.future;
      }),
    );

    final older = viewModel.load();
    final newer = viewModel.load();
    second.complete(ProductList.ready([_product('nova', 'Pizzas')]));
    await newer;
    first.complete(const ProductList.unavailable('antiga'));
    await older;

    expect(viewModel.status, MenuStatus.ready);
    expect(viewModel.visibleProducts.map((product) => product.id), ['nova']);
  });

  test('cardápio vazio é sucesso sem produtos', () async {
    final viewModel = MenuViewModel(FakeProductRepository(() async => ProductList.ready([])));

    await viewModel.load();

    expect(viewModel.isEmpty, isTrue);
  });
}
