import 'dart:async';

import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_repository.dart';
import 'package:dinna/features/client/cart/cart_session.dart';
import 'package:dinna/features/menu/product_image.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_view.dart';
import 'package:dinna/features/recommendation/recommendation_view_model.dart';
import 'package:dinna/features/restaurant/order_format.dart';
import 'package:dinna/shared/widgets/dinna_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';
import 'fake_recommendation_repository.dart';

const _allergy = 'Tem alergia? Confirme os ingredientes com a equipe antes de pedir.';

void main() {
  testWidgets('mostra as perguntas, a alergia e o botão desabilitado', (tester) async {
    await _pump(tester, _model(FakeRecommendationRepository((_) async => _answered())));

    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(find.text(_allergy), findsOneWidget);
    await _see(tester, 'Quanto pretende gastar?');
    await _see(tester, 'Qual é o tamanho da sua fome?');
    await _see(tester, 'Qual proteína prefere?');
    await _see(tester, 'Que tipo de refeição deseja?');
    await _see(tester, 'Prefere salgado ou doce?');
    await _see(tester, 'Possui alguma restrição alimentar?');
    await _see(tester, 'Opcional. Pode marcar várias.');
    for (final restriction in DietaryRestriction.values) {
      await _see(tester, restriction.label);
    }
    await _scrollToSubmit(tester);
    expect(_submitButton(tester).onPressed, isNull);
  });

  testWidgets('seleção única e restrições múltiplas habilitam o botão', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await _pump(tester, _model(FakeRecommendationRepository((_) async => _answered())));

      await _answerForm(tester);
      await _tapLabel(tester, DietaryRestriction.noOnion.label);
      await _tapLabel(tester, DietaryRestriction.noGluten.label);
      await _scrollToSubmit(tester);

      expect(_submitButton(tester).onPressed, isNotNull);
      final onion = find.widgetWithText(CheckboxListTile, 'Sem cebola');
      final gluten = find.widgetWithText(CheckboxListTile, 'Sem glúten');
      final chicken = find.widgetWithText(RadioListTile<MealProtein>, 'Frango');
      await tester.scrollUntilVisible(onion, -400);
      expect(
        tester.getSemantics(onion),
        isSemantics(label: 'Sem cebola', hasCheckedState: true, isChecked: true),
      );
      await tester.scrollUntilVisible(gluten, 200);
      expect(
        tester.getSemantics(gluten),
        isSemantics(label: 'Sem glúten', hasCheckedState: true, isChecked: true),
      );
      await tester.scrollUntilVisible(chicken, -400);
      expect(
        tester.getSemantics(chicken),
        isSemantics(
          label: 'Frango',
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('contradição fica visível e não apaga a escolha', (tester) async {
    await _pump(tester, _model(FakeRecommendationRepository((_) async => _answered())));
    await _answerForm(tester, protein: 'Peixe');
    await _tapLabel(tester, 'Sem frutos do mar');
    expect(find.text(RecommendationViewModel.fishAndSeafoodMessage), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Peixe'), -400);
    expect(find.text('Peixe'), findsWidgets);
    await _scrollToSubmit(tester);
    expect(_submitButton(tester).onPressed, isNull);

    await _tapLabel(tester, 'Sem frutos do mar');
    expect(find.text(RecommendationViewModel.fishAndSeafoodMessage), findsNothing);
    await _scrollToSubmit(tester);
    expect(_submitButton(tester).onPressed, isNotNull);
    await tester.scrollUntilVisible(find.text('Peixe'), -400);
    expect(find.text('Peixe'), findsWidgets);
  });

  testWidgets('loading impede outro envio e o card mostra o prato real', (tester) async {
    final pending = Completer<RecommendationAttempt>();
    final catalog = Completer<ProductList>();
    var calls = 0;
    final burger = _product('p3', name: 'Burger da casa', priceCents: 1890);
    final viewModel = _model(
      FakeRecommendationRepository((_) {
        calls += 1;
        return calls == 1
            ? pending.future
            : Future<RecommendationAttempt>.value(_answered(reason: 'Frango, Salgado'));
      }),
      products: FakeProductRepository(() => catalog.future),
    );
    await _pump(tester, viewModel);
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pump();

    expect(find.text('Preparando uma sugestão…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Quanto pretende gastar?'), findsNothing);
    expect(calls, 1);

    pending.complete(_answered());
    await tester.pump();
    expect(find.text('Preparando uma sugestão…'), findsOneWidget);
    expect(find.text('Burger da casa'), findsNothing);

    catalog.complete(ProductList.ready([burger]));
    await tester.pumpAndSettle();

    expect(find.text('Burger da casa'), findsOneWidget);
    expect(find.text(formatOrderTotal(1890)), findsOneWidget);
    expect(find.text('Carne, Salgado'), findsOneWidget);
    expect(find.text('Descrição interna'), findsNothing);
    expect(find.text('p3'), findsNothing);
    expect(find.text('Adicionar ao carrinho'), findsOneWidget);
    expect(find.byType(ProductImage), findsOneWidget);
    expect(tester.widget<ProductImage>(find.byType(ProductImage)).product, burger);
    expect(find.text(_allergy), findsOneWidget);
    expect(find.text('A Dinna não respondeu agora'), findsNothing);
    expect(find.text('Ver cardápio completo'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Quanto pretende gastar?'), findsOneWidget);
    await _scrollToSubmit(tester);
    expect(_submitButton(tester).onPressed, isNotNull);
    expect(viewModel.budget, MealBudget.upTo20);
  });

  testWidgets('fallback mostra a faixa e a nova tentativa', (tester) async {
    var calls = 0;
    final viewModel = _model(
      FakeRecommendationRepository((_) async {
        calls += 1;
        return RecommendationAttempt.ready(
          Recommendation(
            provider: RecommendationProvider.unavailable,
            outcome: RecommendationOutcome.suggestions,
            products: [RecommendationSuggestion(productId: 'p2', reason: 'Carne, Salgado')],
          ),
        );
      }),
      products: FakeProductRepository(
        () async => ProductList.ready([_product('p2', name: 'Salada da casa', priceCents: 2200)]),
      ),
    );
    await _pump(tester, viewModel);
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();

    expect(find.byType(DinnaBanner), findsWidgets);
    expect(find.text('A Dinna não respondeu agora'), findsOneWidget);
    expect(
      find.text(
        'Seu pedido continua funcionando normalmente. Separei pratos do cardápio que batem com os seus filtros.',
      ),
      findsOneWidget,
    );
    expect(find.text('Salada da casa'), findsOneWidget);
    expect(find.text(formatOrderTotal(2200)), findsOneWidget);
    expect(find.text('Carne, Salgado'), findsOneWidget);
    expect(find.byType(ProductImage), findsOneWidget);
    expect(find.text(_allergy), findsOneWidget);

    await _tapLabel(tester, 'Tentar a Dinna de novo');
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(viewModel.phase, RecommendationPhase.fallback);
  });

  testWidgets('vazio compatível, cardápio vazio e erro com nova tentativa', (tester) async {
    final outcomes = <RecommendationAttempt>[
      RecommendationAttempt.ready(
        Recommendation(
          provider: RecommendationProvider.notCalled,
          outcome: RecommendationOutcome.noCompatibleProducts,
          products: const [],
        ),
      ),
      RecommendationAttempt.ready(
        Recommendation(
          provider: RecommendationProvider.notCalled,
          outcome: RecommendationOutcome.emptyCatalog,
          products: const [],
        ),
      ),
      const RecommendationAttempt.failed(
        RecommendationFailure.unavailable,
        title: 'Não foi possível pedir uma sugestão',
        message: 'O cardápio, o carrinho e o pedido continuam disponíveis.',
      ),
      _answered(reason: 'Frango, Salgado'),
    ];
    var index = 0;
    final viewModel = _model(
      FakeRecommendationRepository((_) async => outcomes[index++]),
      products: FakeProductRepository(
        () async => ProductList.ready([_product('p3', name: 'Burger da casa', priceCents: 1890)]),
      ),
    );
    await _pump(tester, viewModel);
    await _answerForm(tester);

    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    expect(find.text('Nenhum prato compatível'), findsOneWidget);
    expect(
      find.text(
        'Não há, no cardápio disponível, um prato que respeite essas respostas sem completar informação que o cadastro não tem.',
      ),
      findsOneWidget,
    );
    expect(find.text(_allergy), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    expect(find.text('Cardápio vazio'), findsOneWidget);
    expect(
      find.text('O restaurante ainda não tem pratos disponíveis para sugerir.'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível pedir uma sugestão'), findsOneWidget);
    expect(find.text('O cardápio, o carrinho e o pedido continuam disponíveis.'), findsOneWidget);
    expect(find.text('pode ter sido registrado'), findsNothing);

    await _tapLabel(tester, 'Tentar de novo');
    await tester.pumpAndSettle();
    expect(find.text('Burger da casa'), findsOneWidget);
    expect(find.text(formatOrderTotal(1890)), findsOneWidget);
    expect(find.text('Frango, Salgado'), findsOneWidget);
    expect(viewModel.phase, RecommendationPhase.suggestions);
  });

  testWidgets('ver cardápio completo volta para a mesma rota', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: DinnaTheme.light(), home: const _MenuHost()));

    await tester.tap(find.text('abrir recomendação'));
    await tester.pumpAndSettle();
    expect(find.text('Quanto pretende gastar?'), findsOneWidget);

    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await _tapLabel(tester, 'Ver cardápio completo');
    await tester.pumpAndSettle();

    expect(find.text('cardápio mesa 12'), findsOneWidget);
    expect(find.text('Me sugere um prato'), findsNothing);
  });

  testWidgets('mostra os cards na ordem da sugestão e omite prato esgotado', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final salad = _product('p2', name: 'Salada da casa', priceCents: 2200);
    final burger = _product('p1', name: 'Burger da casa', priceCents: 1890);
    await _pump(
      tester,
      _model(
        FakeRecommendationRepository(
          (_) async => RecommendationAttempt.ready(
            Recommendation(
              provider: RecommendationProvider.answered,
              outcome: RecommendationOutcome.suggestions,
              products: [
                RecommendationSuggestion(productId: 'p2', reason: 'Leve, Salgado'),
                RecommendationSuggestion(productId: 'p3', reason: 'Peixe, Salgado'),
                RecommendationSuggestion(productId: 'p1', reason: 'Carne, Salgado'),
              ],
            ),
          ),
        ),
        products: FakeProductRepository(
          () async => ProductList.ready([
            burger,
            _product('p3', name: 'Peixe grelhado', available: false),
            salad,
          ]),
        ),
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();

    expect(find.text('Salada da casa'), findsOneWidget);
    expect(find.text('Burger da casa'), findsOneWidget);
    expect(find.text(formatOrderTotal(2200)), findsOneWidget);
    expect(find.text(formatOrderTotal(1890)), findsOneWidget);
    expect(find.text('Leve, Salgado'), findsOneWidget);
    expect(find.text('Carne, Salgado'), findsOneWidget);
    expect(find.text('Peixe grelhado'), findsNothing);
    expect(find.text('Peixe, Salgado'), findsNothing);
    expect(find.text('p3'), findsNothing);
    expect(find.text('Descrição interna'), findsNothing);
    expect(find.text('Adicionar ao carrinho'), findsNWidgets(2));
    expect(find.byType(ProductImage), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Salada da casa')).dy,
      lessThan(tester.getTopLeft(find.text('Burger da casa')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Leve, Salgado')).dy,
      lessThan(tester.getTopLeft(find.text('Carne, Salgado')).dy),
    );
    expect(
      tester.widgetList<ProductImage>(find.byType(ProductImage)).map((image) => image.product),
      [salad, burger],
    );
  });

  testWidgets('falha ao consultar o cardápio não inventa prato e a nova tentativa mostra o card', (
    tester,
  ) async {
    var calls = 0;
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(() async {
        calls += 1;
        if (calls == 1) return const ProductList.unavailable('timeout cru');
        return ProductList.ready([_product('p3', name: 'Burger da casa', priceCents: 1890)]);
      }),
    );
    await _pump(tester, viewModel);
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();

    expect(find.text(RecommendationViewModel.catalogFailureTitle), findsOneWidget);
    expect(find.text(RecommendationViewModel.catalogFailureMessage), findsOneWidget);
    expect(find.text('timeout cru'), findsNothing);
    expect(find.text('Burger da casa'), findsNothing);
    expect(find.text('Carne, Salgado'), findsNothing);

    await _tapLabel(tester, 'Tentar de novo');
    await tester.pumpAndSettle();

    expect(find.text('Burger da casa'), findsOneWidget);
    expect(find.text(formatOrderTotal(1890)), findsOneWidget);
    expect(find.text('Carne, Salgado'), findsOneWidget);
    expect(find.byType(ProductImage), findsOneWidget);
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(calls, 2);
  });

  testWidgets('sugestão sem prato válido não exibe nome, preço nem motivo', (tester) async {
    await _pump(
      tester,
      _model(
        FakeRecommendationRepository((_) async => _answered()),
        products: FakeProductRepository(
          () async => ProductList.ready([
            _product('p3', name: 'Peixe grelhado', priceCents: 3100, available: false),
          ]),
        ),
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();

    expect(find.text('Nenhum prato disponível'), findsOneWidget);
    expect(
      find.text('As sugestões recebidas não estão no cardápio disponível agora.'),
      findsOneWidget,
    );
    expect(find.text('Peixe grelhado'), findsNothing);
    expect(find.text(formatOrderTotal(3100)), findsNothing);
    expect(find.text('Carne, Salgado'), findsNothing);
    expect(find.text('p3'), findsNothing);
    expect(find.text('Adicionar ao carrinho'), findsNothing);
    expect(find.text(_allergy), findsOneWidget);
    expect(find.text('Ver cardápio completo'), findsOneWidget);
  });

  testWidgets('texto ampliado rola sem overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: RecommendationView(
          createViewModel: () => _model(FakeRecommendationRepository((_) async => _answered())),
          onShowMenu: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _see(tester, 'Sem frutos do mar');
    await _see(tester, 'Me sugere um prato');
    final budget = find.widgetWithText(RadioListTile<MealBudget>, 'Até R\$ 20');
    await tester.scrollUntilVisible(budget, -400);
    final tile = tester.renderObject<RenderBox>(budget);
    expect(tile.size.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('adicionar grava quantidade 1 e abre o carrinho sem fechar a sugestão', (
    tester,
  ) async {
    final repository = _ViewCartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa', priceCents: 1890);

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: RecommendationView(
          createViewModel: () => _model(
            FakeRecommendationRepository((_) async => _answered()),
            products: FakeProductRepository(
              () async => ProductList.ready([burger]),
              onFindById: (_) async => ProductDetail.ready(burger),
            ),
            cartSession: session,
            table: '12',
          ),
          onShowMenu: (_) {},
          onOpenCart: (context) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/cart', arguments: '12'),
                builder: (_) => const Scaffold(body: Text('revisão da mesa 12')),
              ),
            );
          },
        ),
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();

    await _tapLabel(tester, 'Adicionar ao carrinho');
    await tester.pump();

    expect(find.text('Burger da casa adicionado ao carrinho.'), findsOneWidget);
    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(find.text('Carne, Salgado'), findsOneWidget);
    expect(session.read().single.productId, 'p3');
    expect(session.read().single.quantity, 1);

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Ver carrinho')),
      findsOneWidget,
    );
    expect(find.text('Me ajuda a escolher'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Ver carrinho')));
    await tester.pumpAndSettle();

    expect(find.text('revisão da mesa 12'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.text('revisão da mesa 12')))!.settings.arguments,
      '12',
    );

    Navigator.of(tester.element(find.text('revisão da mesa 12'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Burger da casa'), findsOneWidget);
    expect(find.text('Adicionar ao carrinho'), findsOneWidget);
    expect(find.text('Me ajuda a escolher'), findsOneWidget);
  });

  testWidgets('toque duplicado grava uma vez e a falha não fecha a sugestão', (tester) async {
    final gate = Completer<void>();
    final repository = _ViewCartRepository(addGate: gate.future);
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');

    await _pump(
      tester,
      _model(
        FakeRecommendationRepository((_) async => _answered()),
        products: FakeProductRepository(
          () async => ProductList.ready([burger]),
          onFindById: (_) async => ProductDetail.ready(burger),
        ),
        cartSession: session,
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();

    expect(repository.adds, 1);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(session.read(), isEmpty);

    gate.complete();
    await tester.pump();
    expect(find.text('Burger da casa adicionado ao carrinho.'), findsOneWidget);
    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(session.read().single.quantity, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    repository.failure = StateError('falha de disco');
    final addButton = find.widgetWithText(FilledButton, 'Adicionar ao carrinho');
    await tester.scrollUntilVisible(addButton, 400);
    expect(tester.widget<FilledButton>(addButton).onPressed, isNotNull);
    await tester.tap(addButton);
    await tester.pump();
    expect(repository.adds, 2);

    expect(find.text(RecommendationViewModel.addFailureMessage), findsOneWidget);
    expect(find.text('falha de disco'), findsNothing);
    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(find.text('Burger da casa'), findsOneWidget);
    expect(session.read(), hasLength(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('conclusão depois do dispose não navega nem mostra o aviso', (tester) async {
    final gate = Completer<void>();
    final repository = _ViewCartRepository(addGate: gate.future);
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    final navigator = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: DinnaTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecommendationView(
                      createViewModel: () => _model(
                        FakeRecommendationRepository((_) async => _answered()),
                        products: FakeProductRepository(
                          () async => ProductList.ready([burger]),
                          onFindById: (_) async => ProductDetail.ready(burger),
                        ),
                        cartSession: session,
                      ),
                      onShowMenu: (menuContext) => Navigator.of(menuContext).pop(),
                      onOpenCart: (cartContext) {
                        Navigator.of(cartContext).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const Scaffold(body: Text('carrinho indevido')),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
              child: const Text('abrir sugestão'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir sugestão'));
    await tester.pumpAndSettle();
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();
    expect(repository.adds, 1);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Outra rota'))),
    );
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Outra rota'), findsOneWidget);
    expect(find.text('Burger da casa adicionado ao carrinho.'), findsNothing);
    expect(find.text('carrinho indevido'), findsNothing);
    expect(find.text('Me ajuda a escolher'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inclusão concluída fora da rota não publica o aviso', (tester) async {
    final gate = Completer<void>();
    final repository = _ViewCartRepository(addGate: gate.future);
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: RecommendationView(
          createViewModel: () => _model(
            FakeRecommendationRepository((_) async => _answered()),
            products: FakeProductRepository(
              () async => ProductList.ready([burger]),
              onFindById: (_) async => ProductDetail.ready(burger),
            ),
            cartSession: session,
          ),
          onShowMenu: (_) {},
          onOpenCart: (context) {
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('revisão'))));
          },
        ),
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();

    Navigator.of(tester.element(find.text('Me ajuda a escolher')))
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Outra rota'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    gate.complete();
    await tester.pump();

    expect(find.text('Outra rota'), findsOneWidget);
    expect(find.text('Burger da casa adicionado ao carrinho.').hitTestable(), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Ver carrinho').hitTestable(), findsNothing);
    expect(session.read().single.quantity, 1);
  });

  testWidgets('abrir o carrinho dispensa o aviso e não empilha outra revisão', (tester) async {
    final repository = _ViewCartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    var opens = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: RecommendationView(
          createViewModel: () => _model(
            FakeRecommendationRepository((_) async => _answered()),
            products: FakeProductRepository(
              () async => ProductList.ready([burger]),
              onFindById: (_) async => ProductDetail.ready(burger),
            ),
            cartSession: session,
          ),
          onShowMenu: (_) {},
          onOpenCart: (context) {
            opens += 1;
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text('revisão $opens'))));
          },
        ),
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Burger da casa adicionado ao carrinho.').hitTestable(), findsOneWidget);
    final openCart = find.descendant(of: find.byType(AppBar), matching: find.text('Ver carrinho'));
    await tester.tap(openCart);
    await tester.pump();
    await tester.tap(openCart, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('revisão 1'), findsOneWidget);
    expect(find.text('revisão 2'), findsNothing);
    expect(opens, 1);
    expect(find.widgetWithText(SnackBarAction, 'Ver carrinho').hitTestable(), findsNothing);
  });

  testWidgets('voltar ao formulário e pedir de novo não mantém o erro do carrinho', (tester) async {
    final repository = _ViewCartRepository()..failure = StateError('disco cheio');
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');

    await _pump(
      tester,
      _model(
        FakeRecommendationRepository((_) async => _answered()),
        products: FakeProductRepository(
          () async => ProductList.ready([burger]),
          onFindById: (_) async => ProductDetail.ready(burger),
        ),
        cartSession: session,
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();

    expect(find.text(RecommendationViewModel.addFailureMessage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Quanto pretende gastar?'), findsOneWidget);
    expect(find.text(RecommendationViewModel.addFailureMessage), findsNothing);

    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    expect(find.text('Burger da casa'), findsOneWidget);
    expect(find.text(RecommendationViewModel.addFailureMessage), findsNothing);
    expect(session.read(), isEmpty);
  });

  testWidgets('tentar a Dinna de novo apaga o erro da inclusão anterior', (tester) async {
    final repository = _ViewCartRepository()..failure = StateError('disco cheio');
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final salad = _product('p2', name: 'Salada da casa');
    late final RecommendationViewModel viewModel;

    await _pump(
      tester,
      viewModel = _model(
        FakeRecommendationRepository(
          (_) async => RecommendationAttempt.ready(
            Recommendation(
              provider: RecommendationProvider.unavailable,
              outcome: RecommendationOutcome.suggestions,
              products: [RecommendationSuggestion(productId: 'p2', reason: 'Leve, Salgado')],
            ),
          ),
        ),
        products: FakeProductRepository(
          () async => ProductList.ready([salad]),
          onFindById: (_) async => ProductDetail.ready(salad),
        ),
        cartSession: session,
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();

    expect(find.text(RecommendationViewModel.addFailureMessage), findsOneWidget);
    expect(find.text('A Dinna não respondeu agora'), findsOneWidget);

    await _tapLabel(tester, 'Tentar a Dinna de novo');
    await tester.pumpAndSettle();

    expect(viewModel.phase, RecommendationPhase.fallback);
    await tester.scrollUntilVisible(find.text('A Dinna não respondeu agora'), -400);
    expect(find.text('Salada da casa'), findsOneWidget);
    expect(find.text('A Dinna não respondeu agora'), findsOneWidget);
    expect(find.text(RecommendationViewModel.addFailureMessage), findsNothing);
    expect(session.read(), isEmpty);
  });

  testWidgets('lookup pendente bloqueia Ver carrinho até a inclusão terminar', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pending = Completer<ProductDetail>();
    var lookups = 0;
    final repository = _ViewCartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    var opens = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: RecommendationView(
          createViewModel: () => _model(
            FakeRecommendationRepository((_) async => _answered()),
            products: FakeProductRepository(
              () async => ProductList.ready([burger]),
              onFindById: (_) {
                lookups += 1;
                if (lookups == 1) return Future.value(ProductDetail.ready(burger));
                return pending.future;
              },
            ),
            cartSession: session,
          ),
          onShowMenu: (_) {},
          onOpenCart: (context) {
            opens += 1;
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text('revisão $opens'))));
          },
        ),
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(session.read(), hasLength(1));
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();

    final appBarCart = find.descendant(
      of: find.byType(AppBar),
      matching: find.widgetWithText(TextButton, 'Ver carrinho'),
    );
    expect(tester.widget<TextButton>(appBarCart).onPressed, isNull);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Ver carrinho'));
    await tester.pump();
    await tester.tap(appBarCart, warnIfMissed: false);
    await tester.pump();

    expect(opens, 0);
    expect(find.text('revisão 1'), findsNothing);
    expect(session.read(), hasLength(1));

    pending.complete(ProductDetail.ready(burger));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(session.read(), hasLength(2));
    expect(tester.widget<TextButton>(appBarCart).onPressed, isNotNull);
    await tester.tap(appBarCart);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(opens, 1);
    expect(find.text('revisão 1'), findsOneWidget);
  });

  testWidgets('falha tardia da inclusão anterior não aparece na nova sugestão', (tester) async {
    final lookup = Completer<ProductDetail>();
    final repository = _ViewCartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');

    await _pump(
      tester,
      _model(
        FakeRecommendationRepository((_) async => _answered()),
        products: FakeProductRepository(
          () async => ProductList.ready([burger]),
          onFindById: (_) => lookup.future,
        ),
        cartSession: session,
      ),
    );
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar ao carrinho'));
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Quanto pretende gastar?'), findsOneWidget);

    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pump();
    await tester.pump();
    expect(find.text('Burger da casa'), findsOneWidget);

    lookup.complete(const ProductDetail.unavailable('timeout cru'));
    await tester.pump();

    expect(find.text('Burger da casa'), findsOneWidget);
    expect(find.text(RecommendationViewModel.addFailureMessage), findsNothing);
    expect(find.text('Burger da casa adicionado ao carrinho.'), findsNothing);
    expect(find.text('Este prato não está disponível para pedir agora.'), findsNothing);
    expect(session.read(), isEmpty);
  });
}

Future<void> _pump(WidgetTester tester, RecommendationViewModel viewModel) {
  return tester.pumpWidget(
    MaterialApp(
      theme: DinnaTheme.light(),
      home: RecommendationView(createViewModel: () => viewModel, onShowMenu: (_) {}),
    ),
  );
}

Future<void> _see(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 400);
  expect(find.text(text), findsWidgets);
}

Future<void> _tapLabel(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.scrollUntilVisible(finder, 400);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _answerForm(WidgetTester tester, {String protein = 'Frango'}) async {
  await _tapLabel(tester, 'Até R\$ 20');
  await _tapLabel(tester, 'Normal');
  await _tapLabel(tester, protein);
  await _tapLabel(tester, 'Equilibrado');
  await _tapLabel(tester, 'Salgado');
}

RecommendationViewModel _model(
  RecommendationRepository repository, {
  ProductRepository? products,
  CartSession? cartSession,
  String? table,
}) {
  return RecommendationViewModel(
    repository,
    products: products ?? FakeProductRepository(() async => ProductList.ready(const [])),
    cartSession: cartSession,
    table: table,
  );
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

FilledButton _submitButton(WidgetTester tester) {
  final finder = find.widgetWithText(FilledButton, 'Me sugere um prato');
  return tester.widget<FilledButton>(finder);
}

Future<void> _scrollToSubmit(WidgetTester tester) {
  return tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Me sugere um prato'), 400);
}

RecommendationAttempt _answered({String reason = 'Carne, Salgado'}) {
  return RecommendationAttempt.ready(
    Recommendation(
      provider: RecommendationProvider.answered,
      outcome: RecommendationOutcome.suggestions,
      products: [RecommendationSuggestion(productId: 'p3', reason: reason)],
    ),
  );
}

class _ViewCartRepository extends CartRepository {
  _ViewCartRepository({this.addGate});

  final Future<void>? addGate;
  final added = <(String, int)>[];
  Object? failure;
  int adds = 0;

  @override
  Future<List<CartItem>> load() async => const [];

  @override
  Future<CartItem> add({required String productId, required int quantity, String? note}) async {
    adds += 1;
    final gate = addGate;
    if (gate != null) await gate;
    if (failure case final error?) throw error;
    added.add((productId, quantity));
    return CartItem(lineId: 'line-$adds', productId: productId, quantity: quantity, note: note);
  }

  @override
  Future<bool> update(CartItem item) async => false;

  @override
  Future<bool> remove(String lineId) async => false;

  @override
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) async => const [];
}

class _MenuHost extends StatefulWidget {
  const _MenuHost();

  @override
  State<_MenuHost> createState() => _MenuHostState();
}

class _MenuHostState extends State<_MenuHost> {
  var opened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(opened ? 'cardápio mesa 12' : 'cardápio ainda fechado'),
            TextButton(
              onPressed: () {
                setState(() => opened = true);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/recommendation', arguments: '12'),
                    builder: (routeContext) => RecommendationView(
                      createViewModel: () => _model(
                        FakeRecommendationRepository((_) async => _answered()),
                        products: FakeProductRepository(
                          () async => ProductList.ready([
                            _product('p3', name: 'Burger da casa', priceCents: 1890),
                          ]),
                        ),
                        table: '12',
                      ),
                      onShowMenu: (menuContext) => Navigator.of(menuContext).pop(),
                    ),
                  ),
                );
              },
              child: const Text('abrir recomendação'),
            ),
          ],
        ),
      ),
    );
  }
}
