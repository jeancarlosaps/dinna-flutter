import 'dart:async';

import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recommendation_repository.dart';

void main() {
  test('botão fica desabilitado até as cinco escolhas válidas', () async {
    final fake = FakeRecommendationRepository((_) async => _answered());
    final viewModel = RecommendationViewModel(fake);

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
    final viewModel = RecommendationViewModel(fake, table: '12');
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
    final viewModel = RecommendationViewModel(fake);
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
    final viewModel = RecommendationViewModel(
      FakeRecommendationRepository((_) async => outcomes[index++]),
      table: '12',
    );
    _answer(viewModel);
    viewModel.setRestriction(DietaryRestriction.noOnion, selected: true);

    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.suggestions);
    expect(viewModel.suggestions.single.reason, 'Carne, Salgado');
    expect(viewModel.budget, MealBudget.upTo20);

    viewModel.returnToEditing();
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.fallback);
    expect(viewModel.failure, isNull);

    viewModel.returnToEditing();
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.noCompatibleProducts);
    expect(viewModel.suggestions, isEmpty);

    viewModel.returnToEditing();
    await viewModel.submit();
    expect(viewModel.phase, RecommendationPhase.emptyCatalog);

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
    final viewModel = RecommendationViewModel(
      FakeRecommendationRepository((_) {
        calls += 1;
        return calls == 1 ? first.future : second.future;
      }),
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
    final disposable = RecommendationViewModel(FakeRecommendationRepository((_) => late.future));
    _answer(disposable);
    final pending = disposable.submit();
    disposable.dispose();
    late.complete(_answered());
    await pending;
  });
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

RecommendationSuggestion _dish(String id) {
  return RecommendationSuggestion(productId: id, reason: 'Carne, Salgado');
}
