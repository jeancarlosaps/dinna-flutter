import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_preferences_store.dart';
import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_view.dart';
import 'package:dinna/features/recommendation/recommendation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../menu/fake_product_repository.dart';
import 'fake_recommendation_repository.dart';

void main() {
  test('primeira abertura não restaura preferências nem pede sugestão', () async {
    final fake = _repository();
    final viewModel = _model(fake, store: MemoryRecommendationPreferencesStore());

    expect(viewModel.budget, isNull);
    expect(viewModel.hunger, isNull);
    expect(viewModel.protein, isNull);
    expect(viewModel.style, isNull);
    expect(viewModel.taste, isNull);
    expect(viewModel.restrictions, isEmpty);
    expect(viewModel.phase, RecommendationPhase.editing);
    expect(viewModel.canSubmit, isFalse);
    expect(fake.calls, 0);
  });

  test('reabre as cinco respostas sem pedir sugestão', () async {
    final store = MemoryRecommendationPreferencesStore();
    final first = _model(_repository(), store: store);
    _answer(first);
    await first.preferencesSettled;
    first.dispose();

    final fake = _repository();
    final reopened = _model(fake, store: store);

    expect(reopened.budget, MealBudget.upTo20);
    expect(reopened.hunger, MealHunger.normal);
    expect(reopened.protein, MealProtein.chicken);
    expect(reopened.style, MealStyle.balanced);
    expect(reopened.taste, MealTaste.savory);
    expect(reopened.restrictions, isEmpty);
    expect(reopened.phase, RecommendationPhase.editing);
    expect(reopened.canSubmit, isTrue);
    expect(fake.calls, 0);

    await reopened.submit();
    expect(fake.calls, 1);
    expect(fake.lastRequest!.preferences.toJson(), {
      'budget': 'up_to_20',
      'hunger': 'normal',
      'protein': 'chicken',
      'style': 'balanced',
      'taste': 'savory',
    });
  });

  test('persiste e restaura várias restrições', () async {
    final store = MemoryRecommendationPreferencesStore();
    final first = _model(_repository(), store: store);
    _answer(first, protein: MealProtein.vegetarian);
    first.setRestriction(DietaryRestriction.vegan, selected: true);
    first.setRestriction(DietaryRestriction.noLactose, selected: true);
    first.setRestriction(DietaryRestriction.noOnion, selected: true);
    await first.preferencesSettled;

    final fake = _repository();
    final reopened = _model(fake, store: store);

    expect(reopened.restrictions, [
      DietaryRestriction.noOnion,
      DietaryRestriction.noLactose,
      DietaryRestriction.vegan,
    ]);
    expect(fake.calls, 0);
    await reopened.submit();
    expect(fake.calls, 1);
    expect(fake.lastRequest!.preferences.restrictions, [
      DietaryRestriction.noOnion,
      DietaryRestriction.noLactose,
      DietaryRestriction.vegan,
    ]);
  });

  test('restaura o formulário preenchido pela metade e deixa completar', () async {
    final store = MemoryRecommendationPreferencesStore(
      initial: RecommendationSelection(
        budget: MealBudget.from36To60,
        taste: MealTaste.sweet,
        restrictions: [DietaryRestriction.noOnion],
      ),
    );
    final fake = _repository();
    final viewModel = _model(fake, store: store);

    expect(viewModel.budget, MealBudget.from36To60);
    expect(viewModel.hunger, isNull);
    expect(viewModel.protein, isNull);
    expect(viewModel.style, isNull);
    expect(viewModel.taste, MealTaste.sweet);
    expect(viewModel.restrictions, [DietaryRestriction.noOnion]);
    expect(viewModel.canSubmit, isFalse);
    expect(fake.calls, 0);

    viewModel.selectHunger(MealHunger.little);
    viewModel.selectProtein(MealProtein.beef);
    viewModel.selectStyle(MealStyle.full);
    await viewModel.preferencesSettled;

    expect(viewModel.canSubmit, isTrue);
    expect(viewModel.budget, MealBudget.from36To60);
    expect(viewModel.restrictions, [DietaryRestriction.noOnion]);
    await viewModel.submit();
    expect(fake.calls, 1);
    expect(fake.lastRequest!.preferences.taste, MealTaste.sweet);
    expect(fake.lastRequest!.preferences.hunger, MealHunger.little);
  });

  test('alterar uma preferência restaurada grava o novo valor e mantém o resto', () async {
    final store = MemoryRecommendationPreferencesStore(initial: _saved());
    final viewModel = _model(_repository(), store: store);

    viewModel.selectBudget(MealBudget.unlimited);
    await viewModel.preferencesSettled;
    final reopened = _model(_repository(), store: store);

    expect(reopened.budget, MealBudget.unlimited);
    expect(reopened.hunger, MealHunger.normal);
    expect(reopened.protein, MealProtein.chicken);
    expect(reopened.style, MealStyle.balanced);
    expect(reopened.taste, MealTaste.savory);
    expect(store.completed, hasLength(1));
  });

  test('outro ViewModel lê o que o anterior gravou', () async {
    final store = MemoryRecommendationPreferencesStore();
    final first = _model(_repository(), store: store);
    _answer(first, protein: MealProtein.beef);
    await first.preferencesSettled;
    first.dispose();

    final second = _model(_repository(), store: store);

    expect(second.protein, MealProtein.beef);
    expect(second.budget, MealBudget.upTo20);
    expect(second.canSubmit, isTrue);
  });

  test('a gravação termina depois que a tela fecha', () async {
    final store = MemoryRecommendationPreferencesStore();
    final gates = <Completer<void>>[];
    store.delaySaves(() {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    });
    final first = _model(_repository(), store: store);
    first.selectStyle(MealStyle.light);
    final pending = first.preferencesSettled;
    first.dispose();
    await pumpEventQueue();
    gates.single.complete();
    await pending;

    final second = _model(_repository(), store: store);
    expect(second.style, MealStyle.light);
    expect(second.budget, isNull);
  });

  test('arquivo novo lê as preferências depois do reinício', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-preferences-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/recommendation-preferences.json');
    final store = await FileRecommendationPreferencesStore.open(file);
    final first = _model(_repository(), store: store);
    _answer(first);
    first.setRestriction(DietaryRestriction.noGluten, selected: true);
    first.setRestriction(DietaryRestriction.noSeafood, selected: true);
    await first.preferencesSettled;
    first.dispose();

    final reopened = await FileRecommendationPreferencesStore.open(file);
    final fake = _repository();
    final second = _model(fake, store: reopened);

    expect(second.budget, MealBudget.upTo20);
    expect(second.hunger, MealHunger.normal);
    expect(second.protein, MealProtein.chicken);
    expect(second.style, MealStyle.balanced);
    expect(second.taste, MealTaste.savory);
    expect(second.restrictions, [DietaryRestriction.noGluten, DietaryRestriction.noSeafood]);
    expect(fake.calls, 0);
  });

  test('dados ausentes, inválidos ou incompatíveis deixam o formulário usável', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-preferences-');
    addTearDown(() => directory.delete(recursive: true));
    final missing = await FileRecommendationPreferencesStore.open(
      File('${directory.path}/ausente.json'),
    );
    final empty = _model(_repository(), store: missing);
    expect(empty.budget, isNull);
    expect(empty.canSubmit, isFalse);

    final file = File('${directory.path}/recommendation-preferences.json');
    await file.writeAsString('{', flush: true);
    final broken = await FileRecommendationPreferencesStore.open(file);
    final blank = _model(_repository(), store: broken);
    blank.selectHunger(MealHunger.big);
    await blank.preferencesSettled;
    expect(blank.hunger, MealHunger.big);

    await file.writeAsString(
      jsonEncode({
        'budget': 'nope',
        'hunger': 'big',
        'protein': 3,
        'style': 'light',
        'restrictions': ['vegan', 'desconhecida', 1, 'vegan'],
        'products': ['p1'],
        'error': 'falhou',
      }),
      flush: true,
    );
    final partial = await FileRecommendationPreferencesStore.open(file);
    final fake = _repository();
    final viewModel = _model(fake, store: partial);

    expect(viewModel.budget, isNull);
    expect(viewModel.hunger, MealHunger.big);
    expect(viewModel.protein, isNull);
    expect(viewModel.style, MealStyle.light);
    expect(viewModel.taste, isNull);
    expect(viewModel.restrictions, [DietaryRestriction.vegan]);
    expect(fake.calls, 0);

    viewModel.selectBudget(MealBudget.upTo20);
    viewModel.selectProtein(MealProtein.vegetarian);
    viewModel.selectTaste(MealTaste.savory);
    await viewModel.preferencesSettled;
    expect(viewModel.canSubmit, isTrue);
    await viewModel.submit();
    expect(fake.calls, 1);
    expect(fake.lastRequest!.preferences.hunger, MealHunger.big);
    expect(fake.lastRequest!.preferences.protein, MealProtein.vegetarian);
    expect(fake.lastRequest!.preferences.restrictions, [DietaryRestriction.vegan]);
  });

  test('falha ao ler ou gravar não bloqueia o formulário', () async {
    final unreadableRepository = _repository();
    final unreadable = _model(unreadableRepository, store: const _ThrowingReadStore());
    expect(unreadable.budget, isNull);
    expect(unreadable.phase, RecommendationPhase.editing);
    _answer(unreadable);
    await unreadable.submit();
    expect(unreadableRepository.calls, 1);

    final unavailable = _repository();
    final blocked = _model(unavailable, store: const UnavailableRecommendationPreferencesStore());
    _answer(blocked);
    await blocked.preferencesSettled;
    expect(blocked.canSubmit, isTrue);
    await blocked.submit();
    expect(unavailable.calls, 1);

    final store = MemoryRecommendationPreferencesStore();
    final fake = _repository();
    final viewModel = _model(fake, store: store);
    store.failNextSave();
    viewModel.selectBudget(MealBudget.upTo20);
    await viewModel.preferencesSettled;
    expect(viewModel.budget, MealBudget.upTo20);
    expect(store.current, isNull);

    viewModel.selectHunger(MealHunger.little);
    await viewModel.preferencesSettled;
    expect(store.current!.budget, MealBudget.upTo20);
    expect(store.current!.hunger, MealHunger.little);
    viewModel.selectProtein(MealProtein.chicken);
    viewModel.selectStyle(MealStyle.balanced);
    viewModel.selectTaste(MealTaste.savory);
    await viewModel.preferencesSettled;
    await viewModel.submit();
    expect(fake.calls, 1);
    expect(viewModel.phase, isNot(RecommendationPhase.editing));
  });

  test('alterações rápidas terminam na última escolha, sem inverter a gravação', () async {
    final store = MemoryRecommendationPreferencesStore();
    final gates = <Completer<void>>[];
    store.delaySaves(() {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    });
    final fake = _repository();
    final viewModel = _model(fake, store: store);
    final order = [
      MealBudget.upTo20,
      MealBudget.from21To35,
      MealBudget.from36To60,
      MealBudget.unlimited,
    ];

    for (final budget in order) {
      viewModel.selectBudget(budget);
    }
    await _release(gates);
    await viewModel.preferencesSettled;

    expect(store.maxInFlight, 1);
    expect(store.current!.budget, MealBudget.unlimited);
    expect(store.completed.map((selection) => selection.budget).toList(), [MealBudget.unlimited]);
    expect(viewModel.budget, MealBudget.unlimited);
    expect(fake.calls, 0);
  });

  test('falha da escolha seguinte não impede gravar de novo o valor anterior', () async {
    final store = MemoryRecommendationPreferencesStore(
      initial: RecommendationSelection(budget: MealBudget.upTo20),
    );
    final gates = <Completer<void>>[];
    store.delaySaves(() {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    });
    final viewModel = _model(_repository(), store: store);

    viewModel.selectBudget(MealBudget.from21To35);
    await pumpEventQueue();
    viewModel.selectBudget(MealBudget.from36To60);
    gates.single.complete();
    await pumpEventQueue();
    store.failNextSave();
    gates[1].complete();
    await viewModel.preferencesSettled;
    expect(store.current!.budget, MealBudget.from21To35);

    viewModel.selectBudget(MealBudget.upTo20);
    await _release(gates);
    await viewModel.preferencesSettled;

    expect(viewModel.budget, MealBudget.upTo20);
    expect(store.current!.budget, MealBudget.upTo20);
    expect(_model(_repository(), store: store).budget, MealBudget.upTo20);
  });

  test('voltar ao valor anterior durante a gravação não perde essa escolha', () async {
    final store = MemoryRecommendationPreferencesStore(
      initial: RecommendationSelection(budget: MealBudget.upTo20),
    );
    final gates = <Completer<void>>[];
    store.delaySaves(() {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    });
    final viewModel = _model(_repository(), store: store);

    viewModel.selectBudget(MealBudget.from21To35);
    viewModel.selectBudget(MealBudget.upTo20);
    await _release(gates);
    await viewModel.preferencesSettled;

    expect(viewModel.budget, MealBudget.upTo20);
    expect(store.current!.budget, MealBudget.upTo20);
    expect(_model(_repository(), store: store).budget, MealBudget.upTo20);
  });

  test('reabrir durante a gravação não deixa a tela antiga sobrescrever a nova', () async {
    final store = MemoryRecommendationPreferencesStore();
    final gates = <Completer<void>>[];
    store.delaySaves(() {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    });
    final first = _model(_repository(), store: store);
    first.selectBudget(MealBudget.upTo20);
    first.selectBudget(MealBudget.from21To35);

    final second = _model(_repository(), store: store);
    expect(second.budget, MealBudget.from21To35);
    second.selectBudget(MealBudget.unlimited);
    await _release(gates);
    await first.preferencesSettled;
    await second.preferencesSettled;

    expect(store.current!.budget, MealBudget.unlimited);
    expect(store.maxInFlight, 1);
    expect(_model(_repository(), store: store).budget, MealBudget.unlimited);
  });

  test('restaura a contradição e continua bloqueando o envio', () async {
    final store = MemoryRecommendationPreferencesStore(
      initial: RecommendationSelection(
        budget: MealBudget.upTo20,
        hunger: MealHunger.normal,
        protein: MealProtein.fish,
        style: MealStyle.balanced,
        taste: MealTaste.savory,
        restrictions: [DietaryRestriction.noSeafood, DietaryRestriction.noOnion],
      ),
    );
    final fake = _repository();
    final viewModel = _model(fake, store: store);

    expect(viewModel.contradiction, RecommendationViewModel.fishAndSeafoodMessage);
    expect(viewModel.canSubmit, isFalse);
    expect(viewModel.protein, MealProtein.fish);
    expect(viewModel.restrictions, [DietaryRestriction.noOnion, DietaryRestriction.noSeafood]);
    await viewModel.submit();
    expect(fake.calls, 0);

    viewModel.setRestriction(DietaryRestriction.noSeafood, selected: false);
    expect(viewModel.contradiction, isNull);
    expect(viewModel.canSubmit, isTrue);
    expect(viewModel.protein, MealProtein.fish);
    await viewModel.submit();
    expect(fake.calls, 1);
    expect(fake.lastRequest!.preferences.protein, MealProtein.fish);
    expect(fake.lastRequest!.preferences.restrictions, [DietaryRestriction.noOnion]);
  });

  test('proteína animal com vegano restaurado continua contraditória', () async {
    final store = MemoryRecommendationPreferencesStore(
      initial: RecommendationSelection(
        budget: MealBudget.unlimited,
        hunger: MealHunger.big,
        protein: MealProtein.beef,
        style: MealStyle.full,
        taste: MealTaste.savory,
        restrictions: [DietaryRestriction.vegan],
      ),
    );
    final fake = _repository();
    final viewModel = _model(fake, store: store);

    expect(viewModel.contradiction, RecommendationViewModel.animalAndVeganMessage);
    await viewModel.submit();
    expect(fake.calls, 0);

    viewModel.selectProtein(MealProtein.vegetarian);
    expect(viewModel.contradiction, isNull);
    expect(viewModel.canSubmit, isTrue);
    expect(viewModel.restrictions, [DietaryRestriction.vegan]);
  });

  testWidgets('a tela reabre com as respostas marcadas e não pede sugestão', (tester) async {
    final fake = _repository();
    final store = MemoryRecommendationPreferencesStore(
      initial: RecommendationSelection(
        budget: MealBudget.upTo20,
        hunger: MealHunger.normal,
        protein: MealProtein.chicken,
        style: MealStyle.balanced,
        taste: MealTaste.savory,
        restrictions: [DietaryRestriction.noGluten, DietaryRestriction.noLactose],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        home: RecommendationView(
          createViewModel: () => _model(fake, store: store),
          onShowMenu: (_) {},
        ),
      ),
    );

    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(find.text('Quanto pretende gastar?'), findsOneWidget);
    expect(_radio<MealBudget>(MealBudget.upTo20.label).selected, isTrue);
    expect(_radio<MealBudget>(MealBudget.from21To35.label).selected, isFalse);
    expect(fake.calls, 0);

    await tester.scrollUntilVisible(find.text(DietaryRestriction.noLactose.label), 400);
    expect(_check(DietaryRestriction.noGluten.label).value, isTrue);
    expect(_check(DietaryRestriction.noLactose.label).value, isTrue);
    expect(_check(DietaryRestriction.vegan.label).value, isFalse);
    expect(find.text(RecommendationViewModel.fishAndSeafoodMessage), findsNothing);

    final button = find.widgetWithText(FilledButton, 'Me sugere um prato');
    await tester.scrollUntilVisible(button, 400);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(fake.calls, 0);
    await tester.tap(button);
    await tester.pump();
    expect(fake.calls, 1);
  });

  testWidgets('a tela que ficou aberta não apaga a escolha da abertura nova', (tester) async {
    final fake = _repository();
    final store = MemoryRecommendationPreferencesStore();
    final observer = RouteObserver<PageRoute<dynamic>>();
    late RecommendationViewModel covered;

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        navigatorObservers: [observer],
        home: RecommendationView(
          routeObserver: observer,
          createViewModel: () {
            covered = _model(fake, store: store);
            return covered;
          },
          onShowMenu: (_) {},
        ),
      ),
    );

    await tester.tap(find.text(MealBudget.upTo20.label));
    await tester.pump();
    await covered.preferencesSettled;

    late RecommendationViewModel latest;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => RecommendationView(
            routeObserver: observer,
            createViewModel: () {
              latest = _model(fake, store: store);
              return latest;
            },
            onShowMenu: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    latest.setRestriction(DietaryRestriction.noGluten, selected: true);
    await latest.preferencesSettled;
    expect(fake.calls, 0);

    navigator.pop();
    await tester.pumpAndSettle();

    expect(covered.restrictions, [DietaryRestriction.noGluten]);
    await tester.scrollUntilVisible(find.text(DietaryRestriction.noGluten.label), 400);
    expect(_check(DietaryRestriction.noGluten.label).value, isTrue);
    expect(fake.calls, 0);

    await tester.scrollUntilVisible(find.text(MealBudget.from21To35.label), -400);
    await tester.tap(find.text(MealBudget.from21To35.label));
    await tester.pump();
    await covered.preferencesSettled;

    expect(store.current?.budget, MealBudget.from21To35);
    expect(store.current?.restrictions, [DietaryRestriction.noGluten]);
    expect(fake.calls, 0);
  });
}

FakeRecommendationRepository _repository() {
  return FakeRecommendationRepository(
    (_) async => RecommendationAttempt.ready(
      Recommendation(
        provider: RecommendationProvider.answered,
        outcome: RecommendationOutcome.suggestions,
        products: [RecommendationSuggestion(productId: 'p3', reason: 'Frango, Salgado')],
      ),
    ),
  );
}

RecommendationViewModel _model(
  FakeRecommendationRepository repository, {
  required RecommendationPreferencesStore store,
}) {
  return RecommendationViewModel(
    repository,
    products: FakeProductRepository(() async => ProductList.ready(const [])),
    preferencesStore: store,
  );
}

void _answer(RecommendationViewModel viewModel, {MealProtein protein = MealProtein.chicken}) {
  viewModel.selectBudget(MealBudget.upTo20);
  viewModel.selectHunger(MealHunger.normal);
  viewModel.selectProtein(protein);
  viewModel.selectStyle(MealStyle.balanced);
  viewModel.selectTaste(MealTaste.savory);
}

RecommendationSelection _saved() {
  return RecommendationSelection(
    budget: MealBudget.upTo20,
    hunger: MealHunger.normal,
    protein: MealProtein.chicken,
    style: MealStyle.balanced,
    taste: MealTaste.savory,
  );
}

Future<void> _release(List<Completer<void>> gates) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await pumpEventQueue();
    final pending = gates.where((gate) => !gate.isCompleted).toList();
    if (pending.isEmpty) return;
    for (final gate in pending) {
      gate.complete();
    }
  }
  fail('a gravação não terminou');
}

RadioListTile<T> _radio<T>(String label) {
  return find.widgetWithText(RadioListTile<T>, label).evaluate().single.widget as RadioListTile<T>;
}

CheckboxListTile _check(String label) {
  return find.widgetWithText(CheckboxListTile, label).evaluate().single.widget as CheckboxListTile;
}

/// A falha de leitura acontece ao consultar o valor, antes do formulário nascer.
final class _ThrowingReadStore implements RecommendationPreferencesStore {
  const _ThrowingReadStore();

  @override
  RecommendationSelection? get current => throw const RecommendationPreferencesStoreException(
    RecommendationPreferencesStoreProblem.unreadable,
  );

  @override
  Future<void> save(RecommendationSelection selection) async {}
}
