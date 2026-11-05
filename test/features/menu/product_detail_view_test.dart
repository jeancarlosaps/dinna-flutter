import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/menu_view.dart';
import 'package:dinna/features/menu/menu_view_model.dart';
import 'package:dinna/features/menu/product_detail_view.dart';
import 'package:dinna/features/menu/product_detail_view_model.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_product_repository.dart';

Product _product({
  String id = 'p1',
  String name = 'Burger Clássico',
  String description = 'Pão brioche, blend bovino e cheddar',
  bool available = true,
  List<String> ingredients = const ['Pão brioche', 'Carne bovina', 'Queijo cheddar'],
}) => Product(
  id: id,
  name: name,
  description: description,
  category: 'burgers',
  priceCents: 3290,
  imageUrl: null,
  available: available,
  ingredients: ingredients,
);

FakeProductRepository _repository(Future<ProductDetail> Function(String id) onFindById) {
  return FakeProductRepository(() async => ProductList.ready(const []), onFindById: onFindById);
}

Future<void> _pumpDetail(
  WidgetTester tester,
  FakeProductRepository repository, {
  String productId = 'p1',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: DinnaTheme.light(),
      home: Scaffold(
        body: ProductDetailView(
          createViewModel: () => ProductDetailViewModel(repository, productId: productId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra nome, descrição, preço e ingredientes na ordem da API', (tester) async {
    final repository = _repository((_) async => ProductDetail.ready(_product()));

    await _pumpDetail(tester, repository);

    expect(find.text('Burger Clássico'), findsOneWidget);
    expect(find.text('Pão brioche, blend bovino e cheddar'), findsOneWidget);
    expect(find.text('R\$ 32,90'), findsOneWidget);
    expect(find.text('Ingredientes'), findsOneWidget);
    expect(find.text('Pão brioche, Carne bovina, Queijo cheddar'), findsOneWidget);
    expect(find.textContaining('Ingredientes não informados'), findsNothing);
    expect(repository.findCalls, 1);
  });

  testWidgets('sem ingredientes mantém a caixa e orienta a consultar o restaurante', (
    tester,
  ) async {
    final repository = _repository(
      (_) async =>
          ProductDetail.ready(_product(id: 'p5', name: 'Refrigerante Lata', ingredients: const [])),
    );

    await _pumpDetail(tester, repository, productId: 'p5');

    expect(find.text('Ingredientes'), findsOneWidget);
    expect(find.textContaining('Ingredientes não informados'), findsOneWidget);
    expect(find.textContaining('consulte o restaurante'), findsOneWidget);
  });

  testWidgets('produto esgotado mostra o aviso', (tester) async {
    final repository = _repository(
      (_) async => ProductDetail.ready(_product(name: 'Burger Veggie', available: false)),
    );

    await _pumpDetail(tester, repository);

    expect(find.text('Burger Veggie'), findsOneWidget);
    expect(find.text('Este produto está esgotado no momento.'), findsOneWidget);
  });

  testWidgets('falha de rede mostra o erro e tenta de novo', (tester) async {
    var calls = 0;
    final repository = _repository((_) async {
      calls++;
      if (calls == 1) return const ProductDetail.unavailable('Sem conexão');
      return ProductDetail.ready(_product());
    });

    await _pumpDetail(tester, repository);

    expect(find.text('Não foi possível carregar o produto'), findsOneWidget);
    expect(find.text('Sem conexão'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.text('Burger Clássico'), findsOneWidget);
    expect(repository.findCalls, 2);
  });

  testWidgets('produto inexistente mostra que não foi encontrado', (tester) async {
    final repository = _repository(
      (_) async =>
          const ProductDetail.unavailable('Produto não existe', failure: DataFailure.notFound),
    );

    await _pumpDetail(tester, repository);

    expect(find.text('Produto não encontrado'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsNothing);
    expect(find.text('Voltar ao cardápio'), findsOneWidget);
  });

  testWidgets('produto inexistente volta ao cardápio sem buscar de novo', (tester) async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([_product()]),
      onFindById: (_) async =>
          const ProductDetail.unavailable('Produto não existe', failure: DataFailure.notFound),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          table: '12',
          createViewModel: () => MenuViewModel(repository),
          createDetailViewModel: (id) => ProductDetailViewModel(repository, productId: id),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Burger Clássico'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Voltar ao cardápio'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(repository.findCalls, 1);
  });

  testWidgets('ingredientes longos e texto a 200% cabem sem corte numa tela pequena', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const longIngredients = [
      'Chocolate meio amargo',
      'Farinha de trigo',
      'Ovos caipiras',
      'Manteiga sem sal',
      'Açúcar mascavo',
      'Calda de chocolate belga',
      'Sorvete de creme artesanal',
    ];
    final repository = _repository(
      (_) async => ProductDetail.ready(
        _product(name: 'Petit Gateau com sorvete artesanal', ingredients: longIngredients),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ProductDetailView(
              createViewModel: () => ProductDetailViewModel(repository, productId: 'p12'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final ingredients = find.text(longIngredients.join(', '));
    await tester.scrollUntilVisible(ingredients, 100);
    expect(ingredients, findsOneWidget);
  });

  testWidgets('leitor de tela lê o título e os ingredientes juntos', (tester) async {
    final semantics = tester.ensureSemantics();
    final repository = _repository((_) async => ProductDetail.ready(_product()));

    await _pumpDetail(tester, repository);

    expect(
      find.bySemanticsLabel(RegExp(r'Ingredientes\s+Pão brioche, Carne bovina, Queijo cheddar')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('tocar o produto no cardápio abre o detalhe em bottom sheet', (tester) async {
    final products = [_product()];
    final repository = FakeProductRepository(
      () async => ProductList.ready(products),
      onFindById: (_) async => ProductDetail.ready(_product()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          table: '12',
          createViewModel: () => MenuViewModel(repository),
          createDetailViewModel: (id) => ProductDetailViewModel(repository, productId: id),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.findCalls, 0);

    await tester.tap(find.text('Burger Clássico'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Pão brioche, Carne bovina, Queijo cheddar'), findsOneWidget);
    expect(find.text('Mesa 12'), findsOneWidget);
    expect(repository.findCalls, 1);
  });

  testWidgets('bottom sheet deixa o conteúdo acima da barra de navegação do sistema', (
    tester,
  ) async {
    const navigationBar = 48.0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: navigationBar);
    tester.view.viewPadding = const FakeViewPadding(bottom: navigationBar);
    addTearDown(tester.view.reset);

    final repository = FakeProductRepository(
      () async => ProductList.ready([_product()]),
      onFindById: (_) async => ProductDetail.ready(_product()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: MenuView(
          table: '12',
          createViewModel: () => MenuViewModel(repository),
          createDetailViewModel: (id) => ProductDetailViewModel(repository, productId: id),
          onOpenCart: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Burger Clássico'));
    await tester.pumpAndSettle();

    final detail = tester.getRect(find.byType(ProductDetailView));
    expect(detail.bottom, lessThanOrEqualTo(800 - navigationBar));
  });
}
