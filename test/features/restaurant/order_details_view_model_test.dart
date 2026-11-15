import 'dart:async';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_details_view_model.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';
import 'fake_order_repository.dart';
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

  test('usa o name do item e não consulta o cardápio', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Do catálogo')]),
    );
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: sampleOrder(
          id: 'o1',
          table: '4',
          items: [
            OrderItem(
              productId: 'p1',
              quantity: 2,
              note: 'sem cebola',
              name: 'Burger Clássico',
              unitPriceCents: 3290,
              lineTotalCents: 6580,
            ),
          ],
        ),
      ),
    );

    await viewModel.resolveProducts();

    expect(repository.calls, 0);
    expect(viewModel.isResolvingProducts, isFalse);
    expect(viewModel.productLookupMessage, isNull);
    expect(viewModel.items.single.name, 'Burger Clássico');
    expect(viewModel.items.single.lineTotalCents, 6580);
    expect(viewModel.items.single.note, 'sem cebola');
  });

  test('resolve o nome uma vez e ignora outra consulta', () async {
    final gate = Completer<ProductList>();
    final repository = FakeProductRepository(() => gate.future);
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: orderWith(note: 'sem cebola'),
      ),
    );

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
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: orderWith(),
      ),
    );

    await viewModel.resolveProducts();

    expect(viewModel.items.single.name, 'Burger Veggie');
    expect(viewModel.productLookupMessage, isNull);
  });

  test('produto ausente no catálogo recebe um nome de fallback', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'outro', name: 'Suco')]),
    );
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: orderWith(note: 'sem gelo'),
      ),
    );

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
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: orderWith(note: 'sem cebola'),
      ),
    );

    await viewModel.resolveProducts();

    expect(viewModel.isResolvingProducts, isFalse);
    expect(viewModel.productLookupMessage, OrderDetailsViewModel.unexpectedCatalogMessage);
    expect(viewModel.productLookupMessage, isNot(contains(detalheInterno)));
    expect(viewModel.productLookupFailure, DataFailure.unavailable);
    expect(viewModel.table, '4');
    expect(viewModel.status, OrderStatus.preparing);
    expect(viewModel.totalCents, 6580);
    expect(viewModel.items.single.name, OrderDetailsViewModel.unavailableProductName);
    expect(viewModel.items.single.quantity, 2);
    expect(viewModel.items.single.note, 'sem cebola');
  });

  test('mensagem do repository aparece quando o cardápio não carrega', () async {
    final repository = FakeProductRepository(() async => const ProductList.unavailable('sem rede'));
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: orderWith(),
      ),
    );

    await viewModel.resolveProducts();

    expect(viewModel.productLookupMessage, 'sem rede');
    expect(viewModel.productLookupFailure, DataFailure.unavailable);
    expect(viewModel.items.single.name, OrderDetailsViewModel.unavailableProductName);
    expect(viewModel.items.single.quantity, 2);
  });

  test('preserva conflito do cardápio e deixa o detalhe técnico fora da mensagem', () async {
    final repository = FakeProductRepository(
      () async => const ProductList.unavailable(
        'Catálogo em conflito',
        failure: DataFailure.conflict,
        detail: 'Connection refused',
      ),
    );
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: orderWith(),
      ),
    );

    await viewModel.resolveProducts();

    expect(viewModel.productLookupMessage, 'Catálogo em conflito');
    expect(viewModel.productLookupMessage, isNot(contains('Connection refused')));
    expect(viewModel.productLookupFailure, DataFailure.conflict);
    expect(viewModel.table, '4');
  });

  test('observação em branco não entra na linha', () async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Burger Clássico')]),
    );
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: orderWith(note: '   '),
      ),
    );

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
    keep(
      OrderDetailsViewModel(
        repository,
        FakeOrderRepository(() async => OrderList.ready(const [])),
        order: orderWith(note: 'sem cebola'),
      ),
    );
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

  test('após PATCH sem snapshot, preserva nome e totais do pedido carregado', () async {
    final products = FakeProductRepository(() async => ProductList.ready(const []));
    final current = sampleOrder(
      id: 'o1',
      status: OrderStatus.preparing,
      totalCents: 6580,
      items: [
        OrderItem(
          productId: 'p1',
          quantity: 2,
          note: 'sem cebola',
          name: 'Burger Clássico',
          unitPriceCents: 3290,
          lineTotalCents: 6580,
        ),
      ],
    );
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      updateStatus: (id, status) async => OrderUpdate.ready(
        sampleOrder(
          id: 'o1',
          status: OrderStatus.ready,
          totalCents: 6580,
          items: [OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola')],
        ),
      ),
    );
    keep(OrderDetailsViewModel(products, orders, order: current));
    await viewModel.resolveProducts();

    await viewModel.advanceStatus();

    expect(viewModel.status, OrderStatus.ready);
    expect(viewModel.items.single.name, 'Burger Clássico');
    expect(viewModel.items.single.lineTotalCents, 6580);
    expect(viewModel.order.items.single.unitPriceCents, 3290);
  });

  test('avança o status com o próximo passo e esconde o botão ao finalizar', () async {
    final products = FakeProductRepository(() async => ProductList.ready(const []));
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      updateStatus: (id, status) async {
        expect(id, 'o1');
        expect(status, OrderStatus.ready);
        return OrderUpdate.ready(sampleOrder(id: 'o1', status: OrderStatus.ready));
      },
    );
    keep(OrderDetailsViewModel(products, orders, order: orderWith()));

    expect(viewModel.canAdvance, isTrue);
    expect(viewModel.status, OrderStatus.preparing);

    await viewModel.advanceStatus();

    expect(viewModel.status, OrderStatus.ready);
    expect(orders.updateCalls, 1);
    expect(viewModel.actionError, isNull);

    final finishing = FakeOrderRepository(
      () async => OrderList.ready(const []),
      updateStatus: (id, status) async =>
          OrderUpdate.ready(sampleOrder(id: 'o1', status: OrderStatus.finished)),
    );
    keep(
      OrderDetailsViewModel(
        products,
        finishing,
        order: sampleOrder(id: 'o1', status: OrderStatus.ready),
      ),
    );
    await viewModel.advanceStatus();

    expect(viewModel.status, OrderStatus.finished);
    expect(viewModel.canAdvance, isFalse);
  });

  test('em conflito mantém o status e mostra mensagem amigável', () async {
    final products = FakeProductRepository(() async => ProductList.ready(const []));
    final orders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      updateStatus: (id, status) async =>
          const OrderUpdate.unavailable('Não é permitido avançar', failure: DataFailure.conflict),
    );
    keep(OrderDetailsViewModel(products, orders, order: orderWith()));

    await viewModel.advanceStatus();

    expect(viewModel.status, OrderStatus.preparing);
    expect(viewModel.actionError, OrderDetailsViewModel.staleStatusMessage);
    expect(viewModel.actionFailure, DataFailure.conflict);
    expect(viewModel.isUpdating, isFalse);
  });

  test('adopt aplica o pedido novo mesmo com status e total iguais', () {
    final viewModel = OrderDetailsViewModel(
      FakeProductRepository(() async => ProductList.ready(const [])),
      FakeOrderRepository(() async => OrderList.ready(const [])),
      order: sampleOrder(id: 'o1'),
    );
    addTearDown(viewModel.dispose);

    viewModel.adopt(sampleOrder(id: 'o1', orderNumber: 42));

    expect(viewModel.orderNumber, 42);
  });
}
