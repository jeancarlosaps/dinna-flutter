import 'dart:async';

import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';
import 'fake_recommendation_repository.dart';

void main() {
  test('botão fica desabilitado até as cinco escolhas válidas', () async {
    final fake = FakeRecommendationRepository((_) async => _answered());
    final viewModel = _model(fake);

    expect(viewModel.canSubmit, isFalse);
    viewModel.selectBudget(MealBudget.upTo20);
    viewModel.selectHunger(MealHunger.normal);
    viewModel.selectProtein(MealProtein.chicken);
    viewModel.selectStyle(MealStyle.balanced);
    expect(viewModel.canSubmit, isFalse);

    viewModel.selectTaste(MealTaste.savory);
    expect(viewModel.contradiction, isNull);
    expect(viewModel.canSubmit, isTrue);

    await viewModel.submit();
    expect(fake.calls, 1);
    expect(fake.lastRequest!.limit, 3);
    expect(fake.lastRequest!.table, isNull);
    expect(fake.lastRequest!.preferences.toJson().containsKey('restrictions'), isFalse);
  });

  test('contradições bloqueiam o envio e a correção devolve o botão', () async {
    final fake = FakeRecommendationRepository((_) async => _answered());
    final viewModel = _model(fake, table: '12');
    _answer(viewModel, protein: MealProtein.fish);
    viewModel.setRestriction(DietaryRestriction.noSeafood, selected: true);

    expect(viewModel.contradiction, RecommendationViewModel.fishAndSeafoodMessage);
    expect(viewModel.canSubmit, isFalse);
    expect(viewModel.protein, MealProtein.fish);
    expect(viewModel.restrictions, [DietaryRestriction.noSeafood]);
    await viewModel.submit();
    expect(fake.calls, 0);

    viewModel.setRestriction(DietaryRestriction.noSeafood, selected: false);
    expect(viewModel.contradiction, isNull);
    expect(viewModel.canSubmit, isTrue);
    expect(viewModel.protein, MealProtein.fish);
  });

  test('proteína animal com vegano bloqueia e vegetariano com vegano passa', () async {
    final fake = FakeRecommendationRepository((_) async => _answered());
    final viewModel = _model(fake);
    _answer(viewModel, protein: MealProtein.vegetarian);
    viewModel.setRestriction(DietaryRestriction.vegan, selected: true);
    expect(viewModel.contradiction, isNull);
    expect(viewModel.canSubmit, isTrue);

    for (final protein in [MealProtein.chicken, MealProtein.fish, MealProtein.beef]) {
      viewModel.selectProtein(protein);
      expect(
        viewModel.contradiction,
        RecommendationViewModel.animalAndVeganMessage,
        reason: protein.name,
      );
      expect(viewModel.canSubmit, isFalse, reason: protein.name);
      expect(viewModel.restrictions, [DietaryRestriction.vegan], reason: protein.name);
    }

    viewModel.selectProtein(MealProtein.vegetarian);
    expect(viewModel.canSubmit, isTrue);
    await viewModel.submit();
    expect(fake.lastRequest!.table, isNull);
    expect(fake.lastRequest!.preferences.restrictions, [DietaryRestriction.vegan]);
  });

  test('sucesso, fallback, vazios e falha', () async {
    final outcomes = <RecommendationAttempt>[
      _answered(),
      RecommendationAttempt.ready(
        Recommendation(
          provider: RecommendationProvider.unavailable,
          outcome: RecommendationOutcome.suggestions,
          products: [_dish('p2')],
        ),
      ),
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
        RecommendationFailure.validation,
        title: RecommendationRepository.failureTitle,
        message: RecommendationRepository.failureMessage,
      ),
    ];
    var index = 0;
    final catalog = FakeProductRepository(
      () async => ProductList.ready([
        _product('p2', name: 'Salada da casa'),
        _product('p3', name: 'Burger da casa', priceCents: 1890),
      ]),
    );
    final viewModel = _model(
      FakeRecommendationRepository((_) async => outcomes[index++]),
      products: catalog,
      table: '12',
    );
    _answer(viewModel);
    viewModel.setRestriction(DietaryRestriction.noOnion, selected: true);

    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.usedFallback, isFalse);
    expect(viewModel.recommendedProducts.single.reason, 'Carne, Salgado');
    expect(viewModel.recommendedProducts.single.product.name, 'Burger da casa');
    expect(viewModel.recommendedProducts.single.product.priceCents, 1890);
    expect(catalog.calls, 1);
    expect(viewModel.budget, MealBudget.upTo20);

    viewModel.returnToEditing();
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.fallback);
    expect(viewModel.usedFallback, isTrue);
    expect(viewModel.recommendedProducts.single.product.name, 'Salada da casa');
    expect(viewModel.failure, isNull);
    expect(catalog.calls, 2);

    viewModel.returnToEditing();
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.noCompatibleProducts);
    expect(viewModel.recommendedProducts, isEmpty);
    expect(catalog.calls, 2);

    viewModel.returnToEditing();
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.emptyCatalog);
    expect(catalog.calls, 2);

    viewModel.returnToEditing();
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.failed);
    expect(viewModel.failure, RecommendationFailure.validation);
    expect(viewModel.errorMessage, isNot(contains('pode ter sido registrado')));
    expect(viewModel.restrictions, [DietaryRestriction.noOnion]);
    expect(viewModel.budget, MealBudget.upTo20);
  });

  test('ignora toque duplicado, resposta antiga e resposta depois do dispose', () async {
    final first = Completer<RecommendationAttempt>();
    final second = Completer<RecommendationAttempt>();
    var calls = 0;
    final viewModel = _model(
      FakeRecommendationRepository((_) {
        calls += 1;
        return calls == 1 ? first.future : second.future;
      }),
      products: FakeProductRepository(
        () async => ProductList.ready([_product('p3', name: 'Burger da casa')]),
      ),
      table: '7',
    );
    _answer(viewModel);

    final older = viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.loading);
    await viewModel.submit();
    expect(calls, 1);

    viewModel.returnToEditing();
    expect(viewModel.phase, RecommendationPhase.editing);
    expect(viewModel.taste, MealTaste.savory);

    final newer = viewModel.submit();
    second.complete(_answered());
    await newer;
    first.complete(
      const RecommendationAttempt.failed(
        RecommendationFailure.unavailable,
        title: 'Não foi possível confirmar o envio. O pedido pode ter sido registrado.',
        message: 'Não foi possível confirmar o envio. O pedido pode ter sido registrado.',
      ),
    );
    await older;

    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.table, '7');

    final late = Completer<RecommendationAttempt>();
    final disposable = _model(FakeRecommendationRepository((_) => late.future));
    _answer(disposable);
    final pending = disposable.submit();
    disposable.dispose();
    late.complete(_answered());
    await pending;
  });

  test('mantém a ordem das sugestões e ignora prato indisponível', () async {
    final catalog = FakeProductRepository(
      () async => ProductList.ready([
        _product('p1', name: 'Burger da casa', priceCents: 1890),
        _product('p3', name: 'Peixe grelhado', available: false),
        _product('p2', name: 'Salada da casa', priceCents: 2200),
      ]),
    );
    final viewModel = _model(
      FakeRecommendationRepository(
        (_) async => RecommendationAttempt.ready(
          Recommendation(
            provider: RecommendationProvider.answered,
            outcome: RecommendationOutcome.suggestions,
            products: [
              _dish('p2', reason: 'Leve, Salgado'),
              _dish('p3', reason: 'Peixe, Salgado'),
              _dish('p1', reason: 'Carne, Salgado'),
            ],
          ),
        ),
      ),
      products: catalog,
    );
    _answer(viewModel);
    viewModel.setRestriction(DietaryRestriction.noGluten, selected: true);

    await viewModel.submit();

    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p2', 'p1']);
    expect(viewModel.recommendedProducts.map((item) => item.reason), [
      'Leve, Salgado',
      'Carne, Salgado',
    ]);
    expect(viewModel.recommendedProducts.first.product.name, 'Salada da casa');
    expect(viewModel.recommendedProducts.first.product.priceCents, 2200);
    expect(viewModel.recommendedProducts.last.product.name, 'Burger da casa');
    expect(catalog.findCalls, 0);
    expect(viewModel.restrictions, [DietaryRestriction.noGluten]);
  });

  test('sugestões sem prato válido não inventam card e a restrição permanece', () async {
    final catalog = FakeProductRepository(
      () async => ProductList.ready([_product('p3', name: 'Peixe grelhado', available: false)]),
    );
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: catalog,
    );
    _answer(viewModel);
    viewModel.setRestriction(DietaryRestriction.noGluten, selected: true);

    await viewModel.submit();

    expect(viewModel.phase, RecommendationPhase.noAvailableProducts);
    expect(viewModel.recommendedProducts, isEmpty);
    expect(viewModel.usedFallback, isFalse);
    expect(viewModel.failure, isNull);
    expect(viewModel.restrictions, [DietaryRestriction.noGluten]);
    expect(viewModel.protein, MealProtein.chicken);
  });

  test('falha do cardápio não mostra prato e não repete a mensagem técnica', () async {
    final unavailable = FakeProductRepository(
      () async => const ProductList.unavailable('timeout cru', detail: 'SocketException'),
    );
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: unavailable,
    );
    _answer(viewModel);
    await viewModel.submit();

    expect(viewModel.phase, RecommendationPhase.catalogFailed);
    expect(viewModel.recommendedProducts, isEmpty);
    expect(viewModel.failure, isNull);
    expect(viewModel.errorTitle, RecommendationViewModel.catalogFailureTitle);
    expect(viewModel.errorMessage, RecommendationViewModel.catalogFailureMessage);
    expect(viewModel.errorMessage, isNot(contains('timeout')));
    expect(viewModel.errorMessage, isNot(contains('SocketException')));

    final exploding = FakeProductRepository(() async => throw StateError('boom'));
    final again = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: exploding,
    );
    _answer(again);
    await again.submit();
    expect(again.phase, RecommendationPhase.catalogFailed);
    expect(again.recommendedProducts, isEmpty);
    expect(again.errorMessage, isNot(contains('boom')));
  });

  test('ignora o cardápio que chega depois de voltar ou do dispose', () async {
    final recommendation = Completer<RecommendationAttempt>();
    final catalog = Completer<ProductList>();
    final products = FakeProductRepository(() => catalog.future);
    final viewModel = _model(
      FakeRecommendationRepository((_) => recommendation.future),
      products: products,
      table: '7',
    );
    _answer(viewModel);

    final pending = viewModel.submit();
    recommendation.complete(_answered());
    await pumpEventQueue();
    expect(viewModel.phase, RecommendationPhase.loading);
    expect(products.calls, 1);

    viewModel.returnToEditing();
    catalog.complete(ProductList.ready([_product('p3', name: 'Burger da casa')]));
    await pending;

    expect(viewModel.phase, RecommendationPhase.editing);
    expect(viewModel.recommendedProducts, isEmpty);
    expect(viewModel.table, '7');

    final lateRecommendation = Completer<RecommendationAttempt>();
    final lateCatalog = Completer<ProductList>();
    final disposable = _model(
      FakeRecommendationRepository((_) => lateRecommendation.future),
      products: FakeProductRepository(() => lateCatalog.future),
    );
    _answer(disposable);
    final late = disposable.submit();
    lateRecommendation.complete(_answered());
    await pumpEventQueue();
    disposable.dispose();
    lateCatalog.complete(ProductList.ready([_product('p3', name: 'Burger da casa')]));
    await late;
  });
}

RecommendationViewModel _model(
  RecommendationRepository repository, {
  ProductRepository? products,
  String? table,
}) {
  return RecommendationViewModel(
    repository,
    products: products ?? FakeProductRepository(() async => ProductList.ready(const [])),
    table: table,
  );
}

void _answer(RecommendationViewModel viewModel, {MealProtein protein = MealProtein.chicken}) {
  viewModel.selectBudget(MealBudget.upTo20);
  viewModel.selectHunger(MealHunger.normal);
  viewModel.selectProtein(protein);
  viewModel.selectStyle(MealStyle.balanced);
  viewModel.selectTaste(MealTaste.savory);
}

RecommendationAttempt _answered() {
  return RecommendationAttempt.ready(
    Recommendation(
      provider: RecommendationProvider.answered,
      outcome: RecommendationOutcome.suggestions,
      products: [_dish('p3')],
    ),
  );
}

RecommendationSuggestion _dish(String id, {String reason = 'Carne, Salgado'}) {
  return RecommendationSuggestion(productId: id, reason: reason);
}

Product _product(String id, {required String name, int priceCents = 1500, bool available = true}) {
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
