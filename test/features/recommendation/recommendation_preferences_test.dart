import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enums usam os valores e os rótulos do contrato', () {
    expect(MealBudget.values.map((item) => item.value), [
      'up_to_20',
      'from_21_to_35',
      'from_36_to_60',
      'unlimited',
    ]);
    expect(MealBudget.values.map((item) => item.label), [
      'Até R\$ 20',
      'R\$ 21–35',
      'R\$ 36–60',
      'Sem limite',
    ]);
    expect(MealHunger.values.map((item) => item.value), ['little', 'normal', 'big']);
    expect(MealHunger.values.map((item) => item.label), ['Pouca', 'Normal', 'Muita']);
    expect(MealProtein.values.map((item) => item.value), ['chicken', 'fish', 'beef', 'vegetarian']);
    expect(MealProtein.values.map((item) => item.label), [
      'Frango',
      'Peixe',
      'Carne',
      'Vegetariano',
    ]);
    expect(MealStyle.values.map((item) => item.value), ['light', 'balanced', 'full']);
    expect(MealStyle.values.map((item) => item.label), ['Leve', 'Equilibrado', 'Completo']);
    expect(MealTaste.values.map((item) => item.value), ['savory', 'sweet']);
    expect(MealTaste.values.map((item) => item.label), ['Salgado', 'Doce']);
    expect(DietaryRestriction.values.map((item) => item.value), [
      'no_onion',
      'no_gluten',
      'no_lactose',
      'vegan',
      'no_seafood',
    ]);
    expect(DietaryRestriction.values.map((item) => item.label), [
      'Sem cebola',
      'Sem glúten',
      'Sem lactose',
      'Vegano',
      'Sem frutos do mar',
    ]);
  });

  test('serializa as cinco escolhas e omite restrição vazia', () {
    final preferences = RecommendationPreferences(
      budget: MealBudget.from36To60,
      hunger: MealHunger.normal,
      protein: MealProtein.beef,
      style: MealStyle.balanced,
      taste: MealTaste.savory,
    );

    expect(preferences.toJson(), {
      'budget': 'from_36_to_60',
      'hunger': 'normal',
      'protein': 'beef',
      'style': 'balanced',
      'taste': 'savory',
    });
    expect(preferences.toJson().containsKey('restrictions'), isFalse);
    expect(preferences.toJson().containsKey('text'), isFalse);
  });

  test('serializa restrições na ordem do contrato, sem repetir', () {
    final preferences = RecommendationPreferences(
      budget: MealBudget.unlimited,
      hunger: MealHunger.little,
      protein: MealProtein.vegetarian,
      style: MealStyle.light,
      taste: MealTaste.sweet,
      restrictions: const [DietaryRestriction.vegan, DietaryRestriction.noOnion],
    );

    expect(preferences.toJson()['restrictions'], ['no_onion', 'vegan']);
  });

  test('lê restrição ausente como lista vazia e rejeita nulo, repetida e desconhecida', () {
    final read = RecommendationPreferences.fromJson({
      'budget': 'up_to_20',
      'hunger': 'big',
      'protein': 'chicken',
      'style': 'full',
      'taste': 'savory',
    });

    expect(read.restrictions, isEmpty);
    expect(read.toJson().containsKey('restrictions'), isFalse);

    expect(
      () => RecommendationPreferences.fromJson({
        'budget': 'up_to_20',
        'hunger': 'big',
        'protein': 'chicken',
        'style': 'full',
        'taste': 'savory',
        'restrictions': null,
      }),
      throwsFormatException,
    );
    expect(
      () => RecommendationPreferences.fromJson({
        'budget': 'up_to_20',
        'hunger': 'big',
        'protein': 'chicken',
        'style': 'full',
        'taste': 'savory',
        'restrictions': ['no_onion', 'no_onion'],
      }),
      throwsFormatException,
    );
    expect(
      () => RecommendationPreferences.fromJson({
        'budget': 'up_to_20',
        'hunger': 'big',
        'protein': 'chicken',
        'style': 'full',
        'taste': 'savory',
        'restrictions': ['sem_cebola'],
      }),
      throwsFormatException,
    );
  });

  test('rejeita escolha desconhecida, campo extra e pergunta ausente', () {
    expect(() => MealProtein.parse('carne'), throwsFormatException);
    expect(
      () => RecommendationPreferences.fromJson({
        'budget': 'caro',
        'hunger': 'normal',
        'protein': 'beef',
        'style': 'balanced',
        'taste': 'savory',
      }),
      throwsFormatException,
    );
    expect(
      () => RecommendationPreferences.fromJson({
        'budget': 'unlimited',
        'hunger': 'normal',
        'protein': 'beef',
        'style': 'balanced',
        'taste': 'savory',
        'text': 'sem cebola',
      }),
      throwsFormatException,
    );
    expect(
      () => RecommendationPreferences.fromJson({
        'hunger': 'normal',
        'protein': 'beef',
        'style': 'balanced',
        'taste': 'savory',
      }),
      throwsFormatException,
    );
  });

  test('body de exemplo leva mesa, preferências e limit 3', () {
    final request = RecommendationRequest(
      table: '12',
      preferences: RecommendationPreferences(
        budget: MealBudget.from36To60,
        hunger: MealHunger.normal,
        protein: MealProtein.beef,
        style: MealStyle.balanced,
        taste: MealTaste.savory,
        restrictions: const [DietaryRestriction.noOnion],
      ),
    );

    expect(request.toJson(), {
      'table': '12',
      'preferences': {
        'budget': 'from_36_to_60',
        'hunger': 'normal',
        'protein': 'beef',
        'style': 'balanced',
        'taste': 'savory',
        'restrictions': ['no_onion'],
      },
      'limit': 3,
    });
    expect(RecommendationRequest.fromJson(request.toJson()), request);
  });

  test('mesa ausente sai do JSON e limit ausente vale 3', () {
    final request = RecommendationRequest(preferences: _preferences());

    expect(request.toJson().containsKey('table'), isFalse);
    expect(request.limit, 3);

    final read = RecommendationRequest.fromJson({'preferences': _preferences().toJson()});
    expect(read.table, isNull);
    expect(read.limit, 3);
  });

  test('rejeita mesa, limit e preferences fora do contrato', () {
    expect(
      () => RecommendationRequest(table: ' 12', preferences: _preferences()),
      throwsArgumentError,
    );
    expect(
      () => RecommendationRequest(table: '', preferences: _preferences()),
      throwsArgumentError,
    );
    expect(
      () => RecommendationRequest(table: '1' * 41, preferences: _preferences()),
      throwsArgumentError,
    );
    expect(() => RecommendationRequest(preferences: _preferences(), limit: 0), throwsArgumentError);
    expect(() => RecommendationRequest(preferences: _preferences(), limit: 4), throwsArgumentError);

    expect(
      () => RecommendationRequest.fromJson({'preferences': 'sem cebola', 'limit': 3}),
      throwsFormatException,
    );
    expect(
      () => RecommendationRequest.fromJson({'preferences': _preferences().toJson(), 'limit': null}),
      throwsFormatException,
    );
    expect(
      () => RecommendationRequest.fromJson({'preferences': _preferences().toJson(), 'limit': 4}),
      throwsFormatException,
    );
    expect(
      () =>
          RecommendationRequest.fromJson({'preferences': _preferences().toJson(), 'note': 'livre'}),
      throwsFormatException,
    );
  });
}

RecommendationPreferences _preferences() {
  return RecommendationPreferences(
    budget: MealBudget.upTo20,
    hunger: MealHunger.little,
    protein: MealProtein.chicken,
    style: MealStyle.light,
    taste: MealTaste.savory,
  );
}
