import 'dart:async';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_lines.dart';
import 'package:dinna/features/client/cart/cart_view_model.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../menu/fake_product_repository.dart';

void main() {
  CartItem line(String productId, int quantity, [String? note]) {
    return CartItem(productId: productId, quantity: quantity, note: note);
  }

  Product priced(String id, String name, int priceCents) {
    return Product(
      id: id,
      name: name,
      description: '',
      category: 'pratos',
      priceCents: priceCents,
      imageUrl: null,
      available: true,
    );
  }

  CartViewModel viewModelOf(List<CartItem> items, ProductRepository products, {CartLines? lines}) {
    return CartViewModel(products, lines: lines ?? ProcessCartLines(items));
  }

  ProductRepository catalog(List<Product> products) {
    return FakeProductRepository(() async => ProductList.ready(products));
  }

  test('a ligação do processo devolve a lista gravada e protege a leitura', () {
    final lines = ProcessCartLines();
    final item = line('p1', 1);
    lines.write([item]);

    final read = lines.read();
    expect(read, [item]);
    expect(() => read.add(line('p2', 1)), throwsUnsupportedError);
  });

  test('carrinho vazio não consulta o cardápio', () async {
    var calls = 0;
    final viewModel = viewModelOf(
      const [],
      FakeProductRepository(() async {
        calls++;
        return ProductList.ready(const []);
      }),
    );

    await viewModel.resolveProducts();

    expect(calls, 0);
    expect(viewModel.rows, isEmpty);
    expect(viewModel.estimatedTotalCents, isNull);
  });

  test('alterar a quantidade atualiza o total estimado e grava a lista', () async {
    final lines = _RecordingLines([line('p1', 2, 'sem cebola'), line('p2', 1)]);
    final viewModel = viewModelOf(
      const [],
      catalog([priced('p1', 'Moqueca', 4890), priced('p2', 'Salada', 2690)]),
      lines: lines,
    );
    await viewModel.resolveProducts();

    expect(viewModel.estimatedTotalCents, 12470);
    expect(viewModel.rows.first.lineTotalCents, 9780);

    viewModel.increase(0);
    expect(viewModel.rows.first.quantity, 3);
    expect(viewModel.rows.first.note, 'sem cebola');
    expect(viewModel.rows.first.lineTotalCents, 14670);
    expect(viewModel.estimatedTotalCents, 17360);
    expect(lines.writes, 1);
    expect(lines.items.first.quantity, 3);
    expect(lines.items.first.note, 'sem cebola');
    expect(lines.items.last.quantity, 1);

    viewModel.decrease(0);
    expect(viewModel.rows.first.quantity, 2);
    expect(viewModel.estimatedTotalCents, 12470);
    expect(lines.writes, 2);
  });

  test('quantidade 1 não diminui e não grava', () async {
    final lines = _RecordingLines([line('p1', 1)]);
    final viewModel = viewModelOf(const [], catalog([priced('p1', 'Moqueca', 4890)]), lines: lines);
    await viewModel.resolveProducts();

    viewModel.decrease(0);

    expect(viewModel.rows.single.quantity, 1);
    expect(viewModel.estimatedTotalCents, 4890);
    expect(lines.writes, 0);
  });

  test('linhas iguais mudam pela posição, sem fundir produto e observação', () async {
    final lines = _RecordingLines([line('p1', 1, 'sem cebola'), line('p1', 1, 'sem cebola')]);
    final viewModel = viewModelOf(const [], catalog([priced('p1', 'Moqueca', 1000)]), lines: lines);
    await viewModel.resolveProducts();

    viewModel.increase(0);

    expect(viewModel.rows.map((row) => row.quantity), [2, 1]);
    expect(lines.items.map((item) => item.quantity), [2, 1]);
    expect(lines.items.map((item) => item.note), ['sem cebola', 'sem cebola']);
  });

  test('remover item atualiza a lista e o total', () async {
    final lines = _RecordingLines([line('p1', 2), line('p2', 1)]);
    final viewModel = viewModelOf(
      const [],
      catalog([priced('p1', 'Moqueca', 4890), priced('p2', 'Salada', 2690)]),
      lines: lines,
    );
    await viewModel.resolveProducts();

    viewModel.removeAt(0);

    expect(viewModel.rows, hasLength(1));
    expect(viewModel.rows.single.name, 'Salada');
    expect(viewModel.estimatedTotalCents, 2690);
    expect(lines.items, hasLength(1));
    expect(lines.items.single.productId, 'p2');
  });

  test('remover o último item esvazia e grava a lista vazia', () async {
    final lines = _RecordingLines([line('p1', 1)]);
    final viewModel = viewModelOf(const [], catalog([priced('p1', 'Moqueca', 4890)]), lines: lines);
    await viewModel.resolveProducts();

    viewModel.removeAt(0);

    expect(viewModel.rows, isEmpty);
    expect(viewModel.estimatedTotalCents, isNull);
    expect(lines.items, isEmpty);
    expect(lines.writes, 1);
  });

  test('índice fora da lista não grava', () async {
    final lines = _RecordingLines([line('p1', 1)]);
    final viewModel = viewModelOf(const [], catalog([priced('p1', 'Moqueca', 1000)]), lines: lines);
    await viewModel.resolveProducts();

    viewModel.increase(-1);
    viewModel.increase(1);
    viewModel.removeAt(4);

    expect(lines.writes, 0);
    expect(viewModel.rows.single.quantity, 1);
  });

  test('produto sem preço deixa o total estimado ausente e mantém a linha', () async {
    final viewModel = viewModelOf([
      line('p1', 2),
      line('ausente', 1),
    ], catalog([priced('p1', 'Moqueca', 4890)]));
    await viewModel.resolveProducts();

    expect(viewModel.rows.first.lineTotalCents, 9780);
    expect(viewModel.rows.last.name, CartViewModel.missingProductName);
    expect(viewModel.rows.last.lineTotalCents, isNull);
    expect(viewModel.estimatedTotalCents, isNull);
    expect(viewModel.productLookupMessage, isNull);
  });

  test('falha do cardápio mantém as linhas e omite o total', () async {
    final lines = _RecordingLines([line('p1', 2, 'sem cebola')]);
    final viewModel = viewModelOf(
      const [],
      FakeProductRepository(
        () async => const ProductList.unavailable(
          'Não foi possível carregar o cardápio',
          failure: DataFailure.unavailable,
        ),
      ),
      lines: lines,
    );

    await viewModel.resolveProducts();

    expect(viewModel.rows.single.name, CartViewModel.unavailableProductName);
    expect(viewModel.rows.single.quantity, 2);
    expect(viewModel.rows.single.note, 'sem cebola');
    expect(viewModel.rows.single.lineTotalCents, isNull);
    expect(viewModel.estimatedTotalCents, isNull);
    expect(viewModel.productLookupMessage, 'Não foi possível carregar o cardápio');
    expect(lines.items.single.quantity, 2);

    viewModel.increase(0);
    expect(lines.items.single.quantity, 3);
    expect(viewModel.estimatedTotalCents, isNull);
  });

  test('não notifica de novo se a tela for descartada durante o loading', () async {
    final completer = Completer<ProductList>();
    final viewModel = viewModelOf([line('p1', 1)], FakeProductRepository(() => completer.future));
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.resolveProducts();
    expect(notifications, 1);

    viewModel.dispose();
    completer.complete(ProductList.ready([priced('p1', 'Moqueca', 1000)]));
    await pending;

    expect(notifications, 1);
    expect(viewModel.isResolvingProducts, isTrue);
    expect(viewModel.estimatedTotalCents, isNull);
  });

  test('alterar depois do dispose não grava', () async {
    final lines = _RecordingLines([line('p1', 1)]);
    final viewModel = viewModelOf(const [], catalog([priced('p1', 'Moqueca', 1000)]), lines: lines);
    await viewModel.resolveProducts();
    viewModel.dispose();

    viewModel.increase(0);
    viewModel.removeAt(0);

    expect(lines.writes, 0);
    expect(lines.items.single.quantity, 1);
  });
}

class _RecordingLines implements CartLines {
  _RecordingLines(List<CartItem> items) : items = List<CartItem>.of(items);

  List<CartItem> items;
  int writes = 0;

  @override
  List<CartItem> read() => List<CartItem>.unmodifiable(items);

  @override
  void write(List<CartItem> next) {
    writes++;
    items = List<CartItem>.of(next);
  }
}
