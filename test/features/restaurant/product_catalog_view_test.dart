import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/product_catalog_view.dart';
import 'package:dinna/features/restaurant/product_catalog_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';

void main() {
  Future<void> pumpCatalog(
    WidgetTester tester,
    FakeProductRepository repository, {
    Size size = const Size(800, 1600),
    void Function(BuildContext context)? onOpenOrders,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: ProductCatalogView(
          createViewModel: () => ProductCatalogViewModel(repository),
          onOpenOrders: onOpenOrders,
        ),
      ),
    );
  }

  testWidgets('mostra o produto e abre o cadastro', (tester) async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([
        Product(
          id: 'p1',
          name: 'Burger Clássico',
          description: 'Pão e blend',
          category: 'burgers',
          priceCents: 3290,
          imageUrl: null,
          available: true,
          ingredients: const ['Pão'],
        ),
      ]),
      onCreate: (input) async => ProductSave.saved(
        Product(
          id: 'p2',
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

    await pumpCatalog(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Burger Clássico'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(repository.calls, 1);

    await tester.tap(find.text('Novo produto'));
    await tester.pumpAndSettle();

    expect(find.text('Cadastrar produto'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Milkshake');
    await tester.enterText(find.widgetWithText(TextField, 'Categoria'), 'bebidas');
    await tester.enterText(find.widgetWithText(TextField, 'Preço'), '18,90');
    await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar produto'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('Milkshake'), findsOneWidget);
    expect(find.text('Cadastrar produto'), findsNothing);
  });

  testWidgets('preço inválido permanece no formulário', (tester) async {
    final repository = FakeProductRepository(() async => ProductList.ready(const []));
    await pumpCatalog(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Nenhum produto cadastrado'), findsOneWidget);
    await tester.tap(find.text('Novo produto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Milkshake');
    await tester.enterText(find.widgetWithText(TextField, 'Categoria'), 'bebidas');
    await tester.enterText(find.widgetWithText(TextField, 'Preço'), 'caro');
    await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar produto'));
    await tester.pumpAndSettle();

    expect(find.text(ProductCatalogViewModel.priceError), findsOneWidget);
    expect(repository.createCalls, 0);
  });

  testWidgets('no tablet busca, filtra e cadastra em painel', (tester) async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([
        Product(
          id: 'p1',
          name: 'Moqueca de Peixe',
          description: 'Peixe fresco',
          category: 'pratos',
          priceCents: 4890,
          imageUrl: null,
          available: true,
          ingredients: const ['Peixe'],
        ),
      ]),
      onCreate: (input) async => ProductSave.saved(
        Product(
          id: 'p2',
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

    await pumpCatalog(tester, repository, size: const Size(1280, 900));
    await tester.pumpAndSettle();

    expect(find.text('Novo produto'), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);
    await tester.tap(find.text('Moqueca de Peixe'));
    await tester.pumpAndSettle();
    expect(find.text('Editar produto'), findsOneWidget);
    Navigator.of(tester.element(find.text('Editar produto'))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final search = find.byType(TextField);
    await tester.enterText(search, 'inexistente');
    await tester.pump();
    expect(find.text('Nenhum produto encontrado'), findsOneWidget);

    await tester.enterText(search, '');
    await tester.pump();
    expect(find.text('Moqueca de Peixe'), findsOneWidget);

    await tester.tap(find.text('Novo produto'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastrar produto'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Milkshake');
    await tester.enterText(find.widgetWithText(TextField, 'Categoria'), 'bebidas');
    await tester.enterText(find.widgetWithText(TextField, 'Preço'), '18,90');
    await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar produto'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.text('Milkshake'), findsOneWidget);
    expect(find.text('Novo produto'), findsOneWidget);
  });

  testWidgets('a barra de baixo volta para a fila', (tester) async {
    var opened = false;
    final repository = FakeProductRepository(() async => ProductList.ready(const []));
    await pumpCatalog(tester, repository, onOpenOrders: (context) => opened = true);
    await tester.pumpAndSettle();

    expect(find.text('Pedidos'), findsOneWidget);
    await tester.tap(find.text('Pedidos'));
    await tester.pump();

    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falha ao desativar pela lista mostra o motivo', (tester) async {
    final repository = FakeProductRepository(
      () async => ProductList.ready([
        Product(
          id: 'p1',
          name: 'Burger Clássico',
          description: 'Pão e blend',
          category: 'burgers',
          priceCents: 3290,
          imageUrl: null,
          available: true,
          ingredients: const ['Pão'],
        ),
      ]),
      onDeactivate: (id) async => const ProductSave.failed('Sem conexão com o servidor'),
    );
    await pumpCatalog(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.pump();

    expect(repository.deactivateCalls, 1);
    expect(find.text('Sem conexão com o servidor'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });
}
