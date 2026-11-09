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

Product _named(String id, String name, String category) => Product(
  id: id,
  name: name,
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

  test('busca pelo nome ignora maiúsculas, acentos e espaços', () async {
    final viewModel = MenuViewModel(
      FakeProductRepository(
        () async => ProductList.ready([
          _named('1', 'Café expresso', 'bebidas'),
          _named('2', 'Pão de queijo', 'lanches'),
          _named('3', 'Cappuccino', 'bebidas'),
        ]),
      ),
    );
    await viewModel.load();

    viewModel.search('  CAFE ');
    expect(viewModel.isSearching, isTrue);
    var matches = viewModel.groupedMatches();
    expect(matches.keys, ['bebidas']);
    expect(matches['bebidas']!.map((p) => p.id), ['1']);

    viewModel.search('pao   de');
    matches = viewModel.groupedMatches();
    expect(matches.keys, ['lanches']);

    // Acento digitado como caractere combinante: "e" seguido do agudo.
    viewModel.search('cafe${String.fromCharCode(0x301)}');
    expect(viewModel.groupedMatches()['bebidas']!.map((p) => p.id), ['1']);

    viewModel.search('   ');
    expect(viewModel.isSearching, isFalse);
    expect(viewModel.groupedMatches().values.expand((items) => items), hasLength(3));
  });

  test('busca não altera o cardápio completo e continua depois de recarregar', () async {
    final viewModel = MenuViewModel(
      FakeProductRepository(
        () async => ProductList.ready([
          _named('1', 'Margherita', 'pizzas'),
          _named('2', 'Calabresa', 'pizzas'),
        ]),
      ),
    );
    await viewModel.load();

    viewModel.search('marg');
    expect(viewModel.groupedProducts()['pizzas'], hasLength(2));

    await viewModel.load();
    expect(viewModel.query, 'marg');
    expect(viewModel.groupedMatches()['pizzas']!.map((p) => p.id), ['1']);
  });

  test('busca sem resultado não deixa categoria vazia', () async {
    final viewModel = MenuViewModel(
      FakeProductRepository(() async => ProductList.ready([_named('1', 'Suco', 'bebidas')])),
    );
    await viewModel.load();
    var notified = 0;
    viewModel.addListener(() => notified++);

    viewModel.search('lasanha');
    viewModel.search('lasanha');

    expect(viewModel.groupedMatches(), isEmpty);
    expect(notified, 1);
  });

  test('categoria que sumiu ao recarregar volta para todos', () async {
    var calls = 0;
    final viewModel = MenuViewModel(
      FakeProductRepository(() async {
        calls++;
        if (calls == 1) {
          return ProductList.ready([_product('1', 'Pizzas'), _product('2', 'Saladas')]);
        }
        return ProductList.ready([_product('1', 'Pizzas')]);
      }),
    );
    await viewModel.load();
    viewModel.selectCategory('Saladas');

    await viewModel.load();

    expect(viewModel.selectedCategory, isNull);
    expect(viewModel.visibleProducts.map((p) => p.id), ['1']);
  });

  test('categoria que continua no cardápio fica escolhida ao recarregar', () async {
    final viewModel = MenuViewModel(
      FakeProductRepository(
        () async => ProductList.ready([_product('1', 'Pizzas'), _product('2', 'Saladas')]),
      ),
    );
    await viewModel.load();
    viewModel.selectCategory('Saladas');

    await viewModel.load();

    expect(viewModel.selectedCategory, 'Saladas');
  });

  test('load depois do dispose não consulta nem notifica', () async {
    var calls = 0;
    final viewModel = MenuViewModel(
      FakeProductRepository(() async {
        calls++;
        return ProductList.ready(const []);
      }),
    )..dispose();

    await viewModel.load();

    expect(calls, 0);
    expect(viewModel.status, MenuStatus.loading);
  });
}
