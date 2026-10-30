import 'dart:async';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/features/menu/product_detail_view_model.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_product_repository.dart';

void main() {
  const productId = 'p1';

  ProductDetailViewModel viewModelOf(Future<ProductDetail> Function(String id) find) {
    return ProductDetailViewModel(
      FakeProductRepository(() async => ProductList.ready(const []), onFindById: find),
      productId: productId,
    );
  }

  test('começa sem consulta', () {
    final viewModel = viewModelOf(
      (_) async => ProductDetail.ready(sampleProduct(id: productId, name: 'Burger')),
    );

    expect(viewModel.status, ProductDetailStatus.idle);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.product, isNull);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
    expect(viewModel.productId, productId);
  });

  test('fica em loading até a resposta e pronto quando o produto existe', () async {
    final completer = Completer<ProductDetail>();
    final viewModel = viewModelOf((id) {
      expect(id, productId);
      return completer.future;
    });
    final states = <ProductDetailStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    final pending = viewModel.load();

    expect(viewModel.status, ProductDetailStatus.loading);
    expect(viewModel.isLoading, isTrue);
    expect(viewModel.product, isNull);
    expect(viewModel.errorMessage, isNull);

    final product = sampleProduct(id: productId, name: 'Burger Clássico', available: false);
    completer.complete(ProductDetail.ready(product));
    await pending;

    expect(viewModel.status, ProductDetailStatus.ready);
    expect(viewModel.isLoading, isFalse);
    expect(viewModel.product, product);
    expect(viewModel.product!.available, isFalse);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
    expect(states, [ProductDetailStatus.loading, ProductDetailStatus.ready]);
  });

  test('produto ausente falha com a mensagem e o tipo notFound', () async {
    final viewModel = viewModelOf(
      (_) async => const ProductDetail.unavailable(
        'Produto p9 não encontrado',
        failure: DataFailure.notFound,
      ),
    );
    final states = <ProductDetailStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    await viewModel.load();

    expect(states, [ProductDetailStatus.loading, ProductDetailStatus.failed]);
    expect(viewModel.product, isNull);
    expect(viewModel.errorMessage, 'Produto p9 não encontrado');
    expect(viewModel.failure, DataFailure.notFound);
  });

  test('falha de rede guarda a mensagem e deixa o detalhe técnico fora dela', () async {
    final viewModel = viewModelOf(
      (_) async => const ProductDetail.unavailable(
        'Não foi possível conectar à API',
        detail: 'Connection refused',
      ),
    );

    await viewModel.load();

    expect(viewModel.status, ProductDetailStatus.failed);
    expect(viewModel.product, isNull);
    expect(viewModel.errorMessage, 'Não foi possível conectar à API');
    expect(viewModel.errorMessage, isNot(contains('Connection refused')));
    expect(viewModel.failure, DataFailure.unavailable);
  });

  test('não notifica de novo se a tela for descartada durante o loading', () async {
    final completer = Completer<ProductDetail>();
    final viewModel = viewModelOf((_) => completer.future);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.load();
    expect(notifications, 1);

    viewModel.dispose();
    completer.complete(ProductDetail.ready(sampleProduct(id: productId, name: 'Burger')));
    await pending;

    expect(notifications, 1);
    expect(viewModel.status, ProductDetailStatus.loading);
    expect(viewModel.product, isNull);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
  });

  test('load depois do dispose não consulta nem notifica', () async {
    var calls = 0;
    final viewModel = viewModelOf((_) async {
      calls++;
      return ProductDetail.ready(sampleProduct(id: productId, name: 'Burger'));
    });

    viewModel.dispose();
    await viewModel.load();

    expect(calls, 0);
    expect(viewModel.status, ProductDetailStatus.idle);
    expect(viewModel.product, isNull);
    expect(viewModel.errorMessage, isNull);
  });

  test('exceção inesperada sai de loading sem o detalhe interno', () async {
    const detalheInterno = 'falha interna do repository';
    final viewModel = viewModelOf((_) async => throw StateError(detalheInterno));
    final states = <ProductDetailStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    await viewModel.load();

    expect(states, [ProductDetailStatus.loading, ProductDetailStatus.failed]);
    expect(viewModel.product, isNull);
    expect(viewModel.errorMessage, ProductDetailViewModel.unexpectedFailureMessage);
    expect(viewModel.errorMessage, isNot(contains(detalheInterno)));
    expect(viewModel.failure, DataFailure.unavailable);
  });

  test('exceção inesperada depois do dispose termina sem atualizar nem notificar', () async {
    final completer = Completer<ProductDetail>();
    final viewModel = viewModelOf((_) => completer.future);
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.load();
    expect(viewModel.status, ProductDetailStatus.loading);
    expect(notifications, 1);

    viewModel.dispose();
    completer.completeError(StateError('falha interna do repository'));
    await pending;

    expect(notifications, 1);
    expect(viewModel.status, ProductDetailStatus.loading);
    expect(viewModel.product, isNull);
    expect(viewModel.errorMessage, isNull);
  });
}
