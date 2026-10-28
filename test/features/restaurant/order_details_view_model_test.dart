import 'dart:async';

import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_details_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';
import 'sample_order.dart';

void main() {
  late OrderDetailsViewModel viewModel;

  void keep(OrderDetailsViewModel created) {
    viewModel = created;
    addTearDown(viewModel.dispose);
  }

  Future<void> flushAsync() async {
    await Future<void>.value();
    await Future<void>.value();
  }

  Order orderWith({String? note, int quantity = 2, String productId = 'p1'}) {
    return sampleOrder(
      id: 'o1',
      table: '4',
      status: OrderStatus.preparing,
      totalCents: 6580,
      items: [OrderItem(productId: productId, quantity: quantity, note: note)],
    );
  }

  test('resolve o nome uma vez e ignora outra consulta', () async {
    final gate = Completer<ProductList>();
    final repository = FakeProductRepository(() => gate.future);
    keep(OrderDetailsViewModel(repository, order: orderWith(note: 'sem cebola')));

    final pending = viewModel.resolveProducts();
    final ignored = viewModel.resolveProducts();

    expect(viewModel.isResolvingProducts, isTrue);
    expect(viewModel.productLookupMessage, isNull);
    expect(viewModel.table, '4');
    expect(viewModel.items.single.quantity, 2);
    expect(viewModel.items.single.note, 'sem cebola');
    expect(viewModel.items.single.name, OrderDetailsViewModel.pendingProductName);
    expect(repository.calls, 1);

    gate.complete(ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]));
    await pending;
    await ignored;

    expect(repository.calls, 1);
    expect(viewModel.isResolvingProducts, isFalse);
    expect(viewModel.productLookupMessage, isNull);
    expect(viewModel.items.single.name, 'Burger Clássico');
    expect(viewModel.totalCents, 6580);
  });

  test('usa o nome mesmo quando o produto está indisponível no cardápio', () async {
    final repository = FakeProductRepository(
      () async =>
          ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Veggie', available: false)]),
    );
    keep(OrderDetailsViewModel(repository, order: orderWith()));

    await viewModel.resolveProducts();

    expect(viewModel.items.single.name, 'Burger Veggie');
    expect(viewModel.productLookupMessage, isNull);
  });

  test('produto ausente no catálogo recebe um nome de fallback', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'outro', name: 'Suco')]),
    );
    keep(OrderDetailsViewModel(repository, order: orderWith(note: 'sem gelo')));

    await viewModel.resolveProducts();

    expect(viewModel.items.single.name, OrderDetailsViewModel.missingProductName);
    expect(viewModel.items.single.quantity, 2);
    expect(viewModel.items.single.note, 'sem gelo');
    expect(viewModel.productLookupMessage, isNull);
    expect(viewModel.table, '4');
  });

  test('falha do cardápio preserva o pedido e não expõe o detalhe interno', () async {
    const detalheInterno = 'falha interna do repository';
    final repository = FakeProductRepository(() async => throw StateError(detalheInterno));
    keep(OrderDetailsViewModel(repository, order: orderWith(note: 'sem cebola')));

    await viewModel.resolveProducts();

    expect(viewModel.isResolvingProducts, isFalse);
    expect(viewModel.productLookupMessage, OrderDetailsViewModel.unexpectedCatalogMessage);
    expect(viewModel.productLookupMessage, isNot(contains(detalheInterno)));
    expect(viewModel.table, '4');
    expect(viewModel.status, OrderStatus.preparing);
    expect(viewModel.totalCents, 6580);
    expect(viewModel.items.single.name, OrderDetailsViewModel.unavailableProductName);
    expect(viewModel.items.single.quantity, 2);
    expect(viewModel.items.single.note, 'sem cebola');
  });

  test('mensagem do repository aparece quando o cardápio não carrega', () async {
    final repository = FakeProductRepository(() async => const ProductList.unavailable('sem rede'));
    keep(OrderDetailsViewModel(repository, order: orderWith()));

    await viewModel.resolveProducts();

    expect(viewModel.productLookupMessage, 'sem rede');
    expect(viewModel.items.single.name, OrderDetailsViewModel.unavailableProductName);
    expect(viewModel.items.single.quantity, 2);
  });

  test('observação em branco não entra na linha', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]),
    );
    keep(OrderDetailsViewModel(repository, order: orderWith(note: '   ')));

    await viewModel.resolveProducts();

    expect(viewModel.items.single.note, isNull);
    expect(viewModel.items.single.name, 'Burger Clássico');
  });

  test('o domínio não aceita pedido sem itens', () {
    expect(
      () => Order(
        id: 'o1',
        table: '4',
        status: OrderStatus.received,
        items: const <OrderItem>[],
        totalCents: 0,
        createdAt: DateTime.utc(2026, 10, 16, 18),
      ),
      throwsArgumentError,
    );
  });

  test('não notifica nem altera o pedido depois do dispose', () async {
    final gate = Completer<ProductList>();
    final repository = FakeProductRepository(() => gate.future);
    keep(OrderDetailsViewModel(repository, order: orderWith(note: 'sem cebola')));
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.resolveProducts();
    expect(notifications, 1);
    expect(viewModel.isResolvingProducts, isTrue);

    viewModel.dispose();
    gate.complete(ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]));
    await pending;
    await flushAsync();

    expect(notifications, 1);
    expect(repository.calls, 1);
    expect(viewModel.isResolvingProducts, isTrue);
    expect(viewModel.items.single.name, OrderDetailsViewModel.pendingProductName);
    expect(viewModel.items.single.note, 'sem cebola');
    expect(viewModel.table, '4');
  });
}
