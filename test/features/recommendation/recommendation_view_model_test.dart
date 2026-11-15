import 'dart:async';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/client/cart/cart_repository.dart';
import 'package:dinna/features/client/cart/cart_session.dart';
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

  test('inclui o prato válido com quantidade 1 na sessão aberta', () async {
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa', priceCents: 1890);
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) async => ProductDetail.ready(burger),
      ),
      cartSession: session,
      table: '12',
    );
    _answer(viewModel);
    viewModel.setRestriction(DietaryRestriction.noOnion, selected: true);
    await viewModel.submit();

    final result = await viewModel.addRecommended('p3');

    expect(result, isA<RecommendationCartAdded>());
    expect((result as RecommendationCartAdded).productName, 'Burger da casa');
    final line = session.read().single;
    expect(line.lineId, 'line-1');
    expect(line.productId, 'p3');
    expect(line.quantity, 1);
    expect(repository.added, [('p3', 1)]);
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.usedFallback, isFalse);
    expect(viewModel.recommendedProducts.single.reason, 'Carne, Salgado');
    expect(viewModel.table, '12');
    expect(viewModel.restrictions, [DietaryRestriction.noOnion]);
    expect(viewModel.isAdding('p3'), isFalse);
  });

  test('fallback permanece fallback depois da inclusão', () async {
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final salad = _product('p2', name: 'Salada da casa');
    final viewModel = _model(
      FakeRecommendationRepository(
        (_) async => RecommendationAttempt.ready(
          Recommendation(
            provider: RecommendationProvider.unavailable,
            outcome: RecommendationOutcome.suggestions,
            products: [_dish('p2', reason: 'Leve, Salgado')],
          ),
        ),
      ),
      products: FakeProductRepository(
        () async => ProductList.ready([salad]),
        onFindById: (_) async => ProductDetail.ready(salad),
      ),
      cartSession: session,
      table: '7',
    );
    _answer(viewModel);
    await viewModel.submit();

    final result = await viewModel.addRecommended('p2');

    expect(result, isA<RecommendationCartAdded>());
    expect(session.read().single.quantity, 1);
    expect(viewModel.phase, RecommendationPhase.fallback);
    expect(viewModel.usedFallback, isTrue);
    expect(viewModel.recommendedProducts.single.reason, 'Leve, Salgado');
    expect(viewModel.table, '7');
  });

  test('toque duplicado grava uma linha e a falha não publica outra', () async {
    final lookup = Completer<ProductDetail>();
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) => lookup.future,
      ),
      cartSession: session,
    );
    _answer(viewModel);
    await viewModel.submit();

    final first = viewModel.addRecommended('p3');
    final second = viewModel.addRecommended('p3');
    expect(viewModel.isAdding('p3'), isTrue);
    expect(repository.adds, 0);

    lookup.complete(ProductDetail.ready(burger));
    final results = await Future.wait([first, second]);

    expect(results.whereType<RecommendationCartAdded>(), hasLength(1));
    expect(results.whereType<RecommendationCartIgnored>(), hasLength(1));
    expect(repository.added, [('p3', 1)]);
    expect(session.read().single.quantity, 1);
    expect(viewModel.isAdding('p3'), isFalse);
    expect(viewModel.phase, RecommendationPhase.suggestions);

    repository.failure = StateError('disco cheio');
    final failed = await viewModel.addRecommended('p3');
    expect(failed, isA<RecommendationCartRejected>());
    expect(
      (failed as RecommendationCartRejected).message,
      RecommendationViewModel.addFailureMessage,
    );
    expect(failed.message, isNot(contains('disco')));
    expect(session.read(), hasLength(1));
    expect(session.read().single.quantity, 1);
    expect(viewModel.isAdding('p3'), isFalse);
  });

  test('não grava prato ausente, indisponível ou sem sessão pronta', () async {
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    final products = FakeProductRepository(
      () async => ProductList.ready([burger]),
      onFindById: (_) async =>
          ProductDetail.ready(_product('p3', name: 'Burger da casa', available: false)),
    );
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: products,
      cartSession: session,
      table: '4',
    );
    _answer(viewModel);
    await viewModel.submit();

    final missing = await viewModel.addRecommended('p9');
    expect(missing, isA<RecommendationCartRejected>());
    expect(
      (missing as RecommendationCartRejected).message,
      RecommendationViewModel.unavailableProductMessage,
    );
    expect(products.findCalls, 0);

    final unavailable = await viewModel.addRecommended('p3');
    expect(unavailable, isA<RecommendationCartRejected>());
    expect(
      (unavailable as RecommendationCartRejected).message,
      RecommendationViewModel.unavailableProductMessage,
    );
    expect(unavailable.message, isNot(contains('false')));
    expect(products.findCalls, 1);
    expect(repository.adds, 0);
    expect(session.read(), isEmpty);
    expect(viewModel.recommendedProducts.single.reason, 'Carne, Salgado');
    expect(viewModel.table, '4');

    final notFoundProducts = FakeProductRepository(
      () async => ProductList.ready([burger]),
      onFindById: (_) async =>
          const ProductDetail.unavailable('sumiu da base', failure: DataFailure.notFound),
    );
    final notFound = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: notFoundProducts,
      cartSession: session,
    );
    _answer(notFound);
    await notFound.submit();
    final absent = await notFound.addRecommended('p3');
    expect(absent, isA<RecommendationCartRejected>());
    expect(
      (absent as RecommendationCartRejected).message,
      RecommendationViewModel.unavailableProductMessage,
    );
    expect(absent.message, isNot(contains('sumiu')));
    expect(notFoundProducts.findCalls, 1);
    expect(repository.adds, 0);

    final closed = CartSession(_CartRepository());
    addTearDown(closed.dispose);
    final withoutSession = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) async => ProductDetail.ready(burger),
      ),
      table: '4',
    );
    _answer(withoutSession);
    await withoutSession.submit();
    final noCart = await withoutSession.addRecommended('p3');
    expect(noCart, isA<RecommendationCartRejected>());
    expect(
      (noCart as RecommendationCartRejected).message,
      RecommendationViewModel.addFailureMessage,
    );

    final notReady = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) async => ProductDetail.ready(burger),
      ),
      cartSession: closed,
    );
    _answer(notReady);
    await notReady.submit();
    final waiting = await notReady.addRecommended('p3');
    expect(waiting, isA<RecommendationCartRejected>());
    expect(
      (waiting as RecommendationCartRejected).message,
      RecommendationViewModel.addFailureMessage,
    );
    expect(session.read(), isEmpty);
    expect(closed.isReady, isFalse);
  });

  test('falha recuperável da consulta permite tentar de novo', () async {
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    var lookupFails = true;
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) async {
          if (lookupFails) {
            return const ProductDetail.unavailable('timeout cru', failure: DataFailure.unavailable);
          }
          return ProductDetail.ready(burger);
        },
      ),
      cartSession: session,
    );
    _answer(viewModel);
    await viewModel.submit();

    final failed = await viewModel.addRecommended('p3');

    expect(failed, isA<RecommendationCartRejected>());
    expect(
      (failed as RecommendationCartRejected).message,
      RecommendationViewModel.addFailureMessage,
    );
    expect(failed.message, isNot(contains('timeout')));
    expect(repository.adds, 0);
    expect(session.read(), isEmpty);
    expect(viewModel.phase, RecommendationPhase.suggestions);

    lookupFails = false;
    final added = await viewModel.addRecommended('p3');
    expect(added, isA<RecommendationCartAdded>());
    expect(session.read().single.quantity, 1);
    expect(session.read().single.productId, 'p3');
  });

  test('dispose durante a consulta não grava e não notifica de novo', () async {
    final lookup = Completer<ProductDetail>();
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) => lookup.future,
      ),
      cartSession: session,
    );
    _answer(viewModel);
    await viewModel.submit();

    var notifications = 0;
    viewModel.addListener(() => notifications++);
    final pending = viewModel.addRecommended('p3');
    expect(viewModel.isAdding('p3'), isTrue);
    expect(notifications, 1);

    viewModel.dispose();
    lookup.complete(ProductDetail.ready(burger));
    final result = await pending;

    expect(result, isA<RecommendationCartIgnored>());
    expect(repository.adds, 0);
    expect(session.read(), isEmpty);
    expect(notifications, 1);
  });

  test('gravação já enviada termina sem notificar o view model encerrado', () async {
    final write = Completer<CartItem>();
    final repository = _CartRepository(addGate: write.future);
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) async => ProductDetail.ready(burger),
      ),
      cartSession: session,
      table: '9',
    );
    _answer(viewModel);
    await viewModel.submit();

    final pending = viewModel.addRecommended('p3');
    await pumpEventQueue();
    expect(repository.adds, 1);

    var notifications = 0;
    viewModel.addListener(() => notifications++);
    viewModel.dispose();
    write.complete(CartItem(lineId: 'line-1', productId: 'p3', quantity: 1, note: null));
    final result = await pending;

    expect(result, isA<RecommendationCartIgnored>());
    expect(notifications, 0);
    expect(session.read().single.quantity, 1);
    expect(session.read().single.productId, 'p3');
  });

  test('outra sugestão mostra só os pratos novos com as mesmas respostas', () async {
    final responses = [
      _suggestions(['p1', 'p2']),
      _suggestions(['p2', 'p3']),
    ];
    final fake = FakeRecommendationRepository((_) async => responses.removeAt(0));
    final viewModel = _model(fake, products: _anotherCatalog());
    _answer(viewModel);

    await viewModel.submit();
    final firstPreferences = fake.lastRequest!.preferences.toJson();
    expect(viewModel.canRequestAnother, isTrue);

    await viewModel.requestAnother();

    expect(fake.calls, 2);
    expect(fake.lastRequest!.preferences.toJson(), firstPreferences);
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p3']);
  });

  test('outra sugestão sem prato novo avisa e ajustar volta ao formulário', () async {
    final responses = [
      _suggestions(['p1']),
      _suggestions(['p1'], provider: RecommendationProvider.unavailable),
    ];
    final viewModel = _model(
      FakeRecommendationRepository((_) async => responses.removeAt(0)),
      products: _anotherCatalog(),
    );
    _answer(viewModel);
    await viewModel.submit();

    await viewModel.requestAnother();

    expect(viewModel.phase, RecommendationPhase.noOtherSuggestions);
    expect(viewModel.recommendedProducts, isEmpty);
    expect(viewModel.usedFallback, isFalse);
    expect(viewModel.canRequestAnother, isFalse);

    viewModel.returnToEditing();
    expect(viewModel.phase, RecommendationPhase.editing);
    expect(viewModel.budget, MealBudget.upTo20);
  });

  test('novo envio do formulário esquece os pratos já vistos', () async {
    final responses = [
      _suggestions(['p1']),
      _suggestions(['p2']),
      _suggestions(['p1']),
    ];
    final viewModel = _model(
      FakeRecommendationRepository((_) async => responses.removeAt(0)),
      products: _anotherCatalog(),
    );
    _answer(viewModel);
    await viewModel.submit();
    await viewModel.requestAnother();
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p2']);

    viewModel.returnToEditing();
    await viewModel.submit();

    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p1']);
  });

  test('outra sugestão não dispara no fallback nem com POST em curso', () async {
    final gate = Completer<RecommendationAttempt>();
    var calls = 0;
    final viewModel = _model(
      FakeRecommendationRepository((_) {
        calls += 1;
        if (calls == 1) {
          return Future.value(_suggestions(['p1'], provider: RecommendationProvider.unavailable));
        }
        return gate.future;
      }),
      products: _anotherCatalog(),
    );
    _answer(viewModel);

    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.fallback);
    expect(viewModel.canRequestAnother, isFalse);
    await viewModel.requestAnother();
    expect(calls, 1);

    final retry = viewModel.submit();
    expect(viewModel.canRequestAnother, isFalse);
    await viewModel.requestAnother();
    expect(calls, 2);
    gate.complete(_suggestions(['p2']));
    await retry;
    expect(viewModel.canRequestAnother, isTrue);
  });

  test('outra sugestão espera a inclusão pendente e o prato entra uma vez', () async {
    final lookup = Completer<ProductDetail>();
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p1', name: 'Burger da casa');
    final responses = [
      _suggestions(['p1']),
      _suggestions(['p2']),
    ];
    final fake = FakeRecommendationRepository((_) async => responses.removeAt(0));
    final viewModel = _model(
      fake,
      products: FakeProductRepository(
        () async => ProductList.ready([burger, _product('p2', name: 'Frango grelhado')]),
        onFindById: (_) => lookup.future,
      ),
      cartSession: session,
    );
    _answer(viewModel);
    await viewModel.submit();

    final pending = viewModel.addRecommended('p1');
    expect(viewModel.hasPendingAddition, isTrue);
    expect(viewModel.canRequestAnother, isFalse);

    await viewModel.requestAnother();
    expect(fake.calls, 1);
    expect(viewModel.phase, RecommendationPhase.suggestions);

    lookup.complete(ProductDetail.ready(burger));
    final result = await pending;

    expect(result, isA<RecommendationCartAdded>());
    expect(repository.adds, 1);
    expect(repository.added, [('p1', 1)]);
    expect(session.read().single.productId, 'p1');
    expect(session.read().single.quantity, 1);
    expect(viewModel.canRequestAnother, isTrue);

    await viewModel.requestAnother();
    expect(fake.calls, 2);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p2']);
    expect(repository.adds, 1);
  });

  test('tentar de novo após falha não repete prato e mantém as respostas', () async {
    final responses = [
      _suggestions(['p1']),
      const RecommendationAttempt.failed(
        RecommendationFailure.unavailable,
        title: RecommendationRepository.failureTitle,
        message: RecommendationRepository.failureMessage,
      ),
      _suggestions(['p1', 'p2']),
    ];
    final fake = FakeRecommendationRepository((_) async => responses.removeAt(0));
    final viewModel = _model(fake, products: _anotherCatalog());
    _answer(viewModel);
    await viewModel.submit();
    final firstPreferences = fake.lastRequest!.preferences.toJson();

    await viewModel.requestAnother();
    expect(viewModel.phase, RecommendationPhase.failed);

    await viewModel.retry();

    expect(fake.calls, 3);
    expect(fake.lastRequest!.preferences.toJson(), firstPreferences);
    expect(viewModel.budget, MealBudget.upTo20);
    expect(viewModel.protein, MealProtein.chicken);
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p2']);
  });

  test('tentar de novo após falha do cardápio filtra os pratos já vistos', () async {
    var catalogFails = false;
    final responses = [
      _suggestions(['p1']),
      _suggestions(['p1', 'p3']),
      _suggestions(['p1', 'p3']),
    ];
    final viewModel = _model(
      FakeRecommendationRepository((_) async => responses.removeAt(0)),
      products: FakeProductRepository(() async {
        if (catalogFails) return const ProductList.unavailable('offline');
        return _anotherCatalog().list();
      }),
    );
    _answer(viewModel);
    await viewModel.submit();

    catalogFails = true;
    await viewModel.requestAnother();
    expect(viewModel.phase, RecommendationPhase.catalogFailed);

    catalogFails = false;
    await viewModel.retry();

    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p3']);
  });

  test('tentar de novo sem prato novo avisa e o próximo envio recomeça', () async {
    final responses = [
      _suggestions(['p1']),
      const RecommendationAttempt.failed(
        RecommendationFailure.unavailable,
        title: RecommendationRepository.failureTitle,
        message: RecommendationRepository.failureMessage,
      ),
      _suggestions(['p1']),
      _suggestions(['p1']),
    ];
    final viewModel = _model(
      FakeRecommendationRepository((_) async => responses.removeAt(0)),
      products: _anotherCatalog(),
    );
    _answer(viewModel);
    await viewModel.submit();
    await viewModel.requestAnother();

    await viewModel.retry();
    expect(viewModel.phase, RecommendationPhase.noOtherSuggestions);
    expect(viewModel.recommendedProducts, isEmpty);
    expect(viewModel.canRequestAnother, isFalse);

    viewModel.returnToEditing();
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p1']);
  });

  test('fallback do envio mantém a nova tentativa sem filtro e sem outra sugestão', () async {
    final responses = [
      _suggestions(['p1'], provider: RecommendationProvider.unavailable),
      _suggestions(['p1'], provider: RecommendationProvider.unavailable),
    ];
    final viewModel = _model(
      FakeRecommendationRepository((_) async => responses.removeAt(0)),
      products: _anotherCatalog(),
    );
    _answer(viewModel);
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.fallback);
    expect(viewModel.canRequestAnother, isFalse);

    await viewModel.retry();

    expect(viewModel.phase, RecommendationPhase.fallback);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p1']);
    expect(viewModel.canRequestAnother, isFalse);
  });

  test('fallback dentro da sequência filtra na nova tentativa da Dinna', () async {
    final responses = [
      _suggestions(['p1']),
      _suggestions(['p1', 'p2'], provider: RecommendationProvider.unavailable),
      _suggestions(['p2', 'p3']),
    ];
    final viewModel = _model(
      FakeRecommendationRepository((_) async => responses.removeAt(0)),
      products: _anotherCatalog(),
    );
    _answer(viewModel);
    await viewModel.submit();

    await viewModel.requestAnother();
    expect(viewModel.phase, RecommendationPhase.fallback);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p2']);
    expect(viewModel.canRequestAnother, isFalse);

    await viewModel.retry();
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.map((item) => item.product.id), ['p3']);
  });

  test('tentar de novo não dispara com inclusão pendente', () async {
    final lookup = Completer<ProductDetail>();
    final session = CartSession(_CartRepository());
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p1', name: 'Burger da casa');
    final fake = FakeRecommendationRepository(
      (_) async => _suggestions(['p1'], provider: RecommendationProvider.unavailable),
    );
    final viewModel = _model(
      fake,
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) => lookup.future,
      ),
      cartSession: session,
    );
    _answer(viewModel);
    await viewModel.submit();

    final pending = viewModel.addRecommended('p1');
    await viewModel.retry();
    expect(fake.calls, 1);

    lookup.complete(ProductDetail.ready(burger));
    expect(await pending, isA<RecommendationCartAdded>());
    expect(session.read().single.productId, 'p1');
  });

  test('voltar ao formulário durante a consulta conclui a inclusão uma vez', () async {
    final lookup = Completer<ProductDetail>();
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    final fake = FakeRecommendationRepository((_) async => _answered());
    final viewModel = _model(
      fake,
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) => lookup.future,
      ),
      cartSession: session,
    );
    _answer(viewModel);
    await viewModel.submit();

    final pending = viewModel.addRecommended('p3');
    expect(viewModel.hasPendingAddition, isTrue);
    expect(viewModel.phase, RecommendationPhase.suggestions);

    viewModel.returnToEditing();

    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.single.product.id, 'p3');
    expect(viewModel.budget, MealBudget.upTo20);
    expect(viewModel.hunger, MealHunger.normal);
    expect(viewModel.protein, MealProtein.chicken);
    expect(viewModel.style, MealStyle.balanced);
    expect(viewModel.taste, MealTaste.savory);
    expect(fake.calls, 1);
    expect(repository.adds, 0);

    lookup.complete(ProductDetail.ready(burger));
    final result = await pending;

    expect(result, isA<RecommendationCartAdded>());
    expect((result as RecommendationCartAdded).productName, 'Burger da casa');
    expect(repository.adds, 1);
    expect(repository.added, [('p3', 1)]);
    expect(session.read(), hasLength(1));
    expect(session.read().single.productId, 'p3');
    expect(session.read().single.quantity, 1);
    expect(viewModel.hasPendingAddition, isFalse);
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(fake.calls, 1);

    viewModel.returnToEditing();
    expect(viewModel.phase, RecommendationPhase.editing);
    expect(viewModel.budget, MealBudget.upTo20);
    expect(viewModel.protein, MealProtein.chicken);
    expect(session.read(), hasLength(1));
    expect(fake.calls, 1);
  });

  test('voltar ao formulário durante a gravação conclui a inclusão uma vez', () async {
    final write = Completer<CartItem>();
    final repository = _CartRepository(addGate: write.future);
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    final fake = FakeRecommendationRepository((_) async => _answered());
    final viewModel = _model(
      fake,
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) async => ProductDetail.ready(burger),
      ),
      cartSession: session,
    );
    _answer(viewModel);
    await viewModel.submit();

    final pending = viewModel.addRecommended('p3');
    await pumpEventQueue();
    expect(repository.adds, 1);
    expect(viewModel.hasPendingAddition, isTrue);

    viewModel.returnToEditing();
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.recommendedProducts.single.product.id, 'p3');
    expect(viewModel.budget, MealBudget.upTo20);
    expect(fake.calls, 1);

    write.complete(CartItem(lineId: 'line-1', productId: 'p3', quantity: 1, note: null));
    final result = await pending;

    expect(result, isA<RecommendationCartAdded>());
    expect(repository.adds, 1);
    expect(repository.added, [('p3', 1)]);
    expect(session.read(), hasLength(1));
    expect(session.read().single.quantity, 1);
    expect(viewModel.hasPendingAddition, isFalse);
    expect(viewModel.phase, RecommendationPhase.suggestions);

    viewModel.returnToEditing();
    expect(viewModel.phase, RecommendationPhase.editing);
    expect(session.read(), hasLength(1));
    expect(fake.calls, 1);
  });

  test('voltar ao formulário durante a consulta preserva a falha da inclusão', () async {
    final lookup = Completer<ProductDetail>();
    final repository = _CartRepository();
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    final burger = _product('p3', name: 'Burger da casa');
    final viewModel = _model(
      FakeRecommendationRepository((_) async => _answered()),
      products: FakeProductRepository(
        () async => ProductList.ready([burger]),
        onFindById: (_) => lookup.future,
      ),
      cartSession: session,
    );
    _answer(viewModel);
    await viewModel.submit();

    final pending = viewModel.addRecommended('p3');
    viewModel.returnToEditing();
    expect(viewModel.phase, RecommendationPhase.suggestions);

    lookup.complete(
      const ProductDetail.unavailable('timeout cru', failure: DataFailure.unavailable),
    );
    final result = await pending;

    expect(result, isA<RecommendationCartRejected>());
    expect(
      (result as RecommendationCartRejected).message,
      RecommendationViewModel.addFailureMessage,
    );
    expect(repository.adds, 0);
    expect(session.read(), isEmpty);
    expect(viewModel.hasPendingAddition, isFalse);
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.budget, MealBudget.upTo20);

    viewModel.returnToEditing();
    expect(viewModel.phase, RecommendationPhase.editing);
    expect(viewModel.recommendedProducts, isEmpty);
    expect(session.read(), isEmpty);
  });
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

class _CartRepository extends CartRepository {
  _CartRepository({this.addGate});

  final Future<CartItem>? addGate;
  final added = <(String, int)>[];
  Object? failure;
  int adds = 0;

  @override
  Future<List<CartItem>> load() async => const [];

  @override
  Future<CartItem> add({required String productId, required int quantity, String? note}) async {
    adds += 1;
    final gate = addGate;
    final item = gate == null
        ? CartItem(lineId: 'line-$adds', productId: productId, quantity: quantity, note: note)
        : await gate;
    if (failure case final error?) throw error;
    added.add((productId, quantity));
    return item;
  }

  @override
  Future<bool> update(CartItem item) async => false;

  @override
  Future<bool> remove(String lineId) async => false;

  @override
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) async => const [];
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

RecommendationAttempt _suggestions(
  List<String> ids, {
  RecommendationProvider provider = RecommendationProvider.answered,
}) {
  return RecommendationAttempt.ready(
    Recommendation(
      provider: provider,
      outcome: RecommendationOutcome.suggestions,
      products: [for (final id in ids) _dish(id)],
    ),
  );
}

FakeProductRepository _anotherCatalog() {
  return FakeProductRepository(
    () async => ProductList.ready([
      _product('p1', name: 'Burger da casa'),
      _product('p2', name: 'Frango grelhado'),
      _product('p3', name: 'Picanha na chapa'),
    ]),
  );
}
