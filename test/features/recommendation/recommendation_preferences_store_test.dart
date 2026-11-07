import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arquivo ausente não inventa preferência', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-preferences-');
    addTearDown(() => directory.delete(recursive: true));
    final store = await FileRecommendationPreferencesStore.open(
      File('${directory.path}/recommendation-preferences.json'),
    );

    expect(store.current, isNull);
  });

  test('grava o formulário e uma instância nova lê o mesmo arquivo', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-preferences-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/recommendation-preferences.json');
    final store = await FileRecommendationPreferencesStore.open(file);
    final selection = _selection(
      restrictions: [DietaryRestriction.vegan, DietaryRestriction.noGluten],
    );

    await store.save(selection);
    final reopened = await FileRecommendationPreferencesStore.open(file);
    final decoded = jsonDecode(await file.readAsString());

    expect(reopened.current, selection);
    expect(decoded, isA<Map<String, dynamic>>());
    final saved = decoded as Map<String, dynamic>;
    expect(saved.keys.toSet(), {'budget', 'hunger', 'protein', 'style', 'taste', 'restrictions'});
    final restrictions = saved['restrictions'];
    expect(restrictions, ['no_gluten', 'vegan']);
  });

  test('json inválido e valores incompatíveis não derrubam a leitura', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-preferences-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/recommendation-preferences.json');
    await file.writeAsString('{', flush: true);
    final broken = await FileRecommendationPreferencesStore.open(file);

    expect(broken.current, isNull);

    await file.writeAsString(
      jsonEncode({
        'budget': 'nope',
        'hunger': 'big',
        'protein': 4,
        'style': 'light',
        'taste': null,
        'restrictions': ['vegan', 'nope', 1, 'vegan'],
        'products': ['p1'],
        'phase': 'loading',
      }),
      flush: true,
    );
    final partial = await FileRecommendationPreferencesStore.open(file);

    expect(partial.current, isNotNull);
    expect(partial.current!.budget, isNull);
    expect(partial.current!.hunger, MealHunger.big);
    expect(partial.current!.protein, isNull);
    expect(partial.current!.style, MealStyle.light);
    expect(partial.current!.taste, isNull);
    expect(partial.current!.restrictions, [DietaryRestriction.vegan]);
  });

  test('escrita concluída permanece quando a escolha seguinte falha', () async {
    final store = MemoryRecommendationPreferencesStore();
    final gates = <Completer<void>>[];
    store.delaySaves(() {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    });
    final original = _selection();
    final first = store.save(original);
    await pumpEventQueue();
    final second = store.save(_selection(budget: MealBudget.unlimited));
    gates.single.complete();
    await pumpEventQueue();
    expect(store.completed, [original]);
    store.failNextSave();
    gates[1].complete();

    await expectLater(second, throwsA(isA<RecommendationPreferencesStoreException>()));
    await first;
    expect(store.current, original);
    expect(store.completed, [original]);
  });

  test('gravações pedidas juntas terminam na última e não correm juntas', () async {
    final store = MemoryRecommendationPreferencesStore();
    final gates = <Completer<void>>[];
    store.delaySaves(() {
      final gate = Completer<void>();
      gates.add(gate);
      return gate.future;
    });
    final first = _selection(budget: MealBudget.upTo20);
    final second = _selection(budget: MealBudget.unlimited);

    final firstSave = store.save(first);
    final secondSave = store.save(second);
    await pumpEventQueue();
    expect(gates, hasLength(1));
    expect(store.maxInFlight, 1);
    gates.single.complete();
    await Future.wait([firstSave, secondSave]);

    expect(store.current, second);
    expect(store.completed, [second]);
    expect(store.maxInFlight, 1);
  });

  test('uma gravação que falha conserva a anterior e a seguinte segue valendo', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-preferences-');
    addTearDown(() async {
      final type = await FileSystemEntity.type(directory.path);
      if (type == FileSystemEntityType.directory) {
        await directory.delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(directory.path).delete();
      }
    });
    final file = File('${directory.path}/recommendation-preferences.json');
    final store = await FileRecommendationPreferencesStore.open(file);
    final original = _selection();
    await store.save(original);
    await directory.delete(recursive: true);
    await File(directory.path).writeAsString('ocupado', flush: true);

    await expectLater(
      store.save(_selection(budget: MealBudget.unlimited)),
      throwsA(
        isA<RecommendationPreferencesStoreException>().having(
          (error) => error.problem,
          'problem',
          RecommendationPreferencesStoreProblem.unwritable,
        ),
      ),
    );
    expect(store.current, original);
  });

  test('diretório indisponível devolve armazenamento que não grava', () async {
    final store = await openRecommendationPreferencesStore(
      applicationSupportDirectory: () async => throw const FileSystemException('negado'),
    );

    expect(store, isA<UnavailableRecommendationPreferencesStore>());
    expect(store.current, isNull);
    await expectLater(
      store.save(_selection()),
      throwsA(isA<RecommendationPreferencesStoreException>()),
    );
  });
}

RecommendationSelection _selection({
  MealBudget budget = MealBudget.from21To35,
  List<DietaryRestriction> restrictions = const [],
}) {
  return RecommendationSelection(
    budget: budget,
    hunger: MealHunger.normal,
    protein: MealProtein.chicken,
    style: MealStyle.balanced,
    taste: MealTaste.savory,
    restrictions: restrictions,
  );
}
