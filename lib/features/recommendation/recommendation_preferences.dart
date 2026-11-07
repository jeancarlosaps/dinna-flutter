import '../../core/domain/json_values.dart';

/// Orçamento do formulário. O [value] é o que viaja no JSON.
enum MealBudget {
  upTo20('up_to_20', 'Até R\$ 20'),
  from21To35('from_21_to_35', 'R\$ 21–35'),
  from36To60('from_36_to_60', 'R\$ 36–60'),
  unlimited('unlimited', 'Sem limite');

  const MealBudget(this.value, this.label);

  final String value;
  final String label;

  static MealBudget parse(String raw) {
    for (final budget in MealBudget.values) {
      if (budget.value == raw) return budget;
    }
    throw FormatException('budget desconhecido: $raw');
  }
}

/// Tamanho da fome. Não recebe default quando a pergunta fica em branco.
enum MealHunger {
  little('little', 'Pouca'),
  normal('normal', 'Normal'),
  big('big', 'Muita');

  const MealHunger(this.value, this.label);

  final String value;
  final String label;

  static MealHunger parse(String raw) {
    for (final hunger in MealHunger.values) {
      if (hunger.value == raw) return hunger;
    }
    throw FormatException('hunger desconhecido: $raw');
  }
}

/// Proteína preferida. "Carne" é [beef]; frango e peixe têm valor próprio.
enum MealProtein {
  chicken('chicken', 'Frango'),
  fish('fish', 'Peixe'),
  beef('beef', 'Carne'),
  vegetarian('vegetarian', 'Vegetariano');

  const MealProtein(this.value, this.label);

  final String value;
  final String label;

  static MealProtein parse(String raw) {
    for (final protein in MealProtein.values) {
      if (protein.value == raw) return protein;
    }
    throw FormatException('protein desconhecido: $raw');
  }
}

/// Leve, equilibrado ou completo. Obrigatório no contrato e sem default.
enum MealStyle {
  light('light', 'Leve'),
  balanced('balanced', 'Equilibrado'),
  full('full', 'Completo');

  const MealStyle(this.value, this.label);

  final String value;
  final String label;

  static MealStyle parse(String raw) {
    for (final style in MealStyle.values) {
      if (style.value == raw) return style;
    }
    throw FormatException('style desconhecido: $raw');
  }
}

/// Doce ou salgado.
enum MealTaste {
  savory('savory', 'Salgado'),
  sweet('sweet', 'Doce');

  const MealTaste(this.value, this.label);

  final String value;
  final String label;

  static MealTaste parse(String raw) {
    for (final taste in MealTaste.values) {
      if (taste.value == raw) return taste;
    }
    throw FormatException('taste desconhecido: $raw');
  }
}

/// Restrição alimentar. A ordem deste enum é a ordem estável do contrato.
enum DietaryRestriction {
  noOnion('no_onion', 'Sem cebola'),
  noGluten('no_gluten', 'Sem glúten'),
  noLactose('no_lactose', 'Sem lactose'),
  vegan('vegan', 'Vegano'),
  noSeafood('no_seafood', 'Sem frutos do mar');

  const DietaryRestriction(this.value, this.label);

  final String value;
  final String label;

  static DietaryRestriction parse(String raw) {
    for (final restriction in DietaryRestriction.values) {
      if (restriction.value == raw) return restriction;
    }
    throw FormatException('restrictions desconhecido: $raw');
  }
}

const _preferenceKeys = {'budget', 'hunger', 'protein', 'style', 'taste', 'restrictions'};

/// Objeto `preferences` de `POST /ai/recommendation`.
///
/// As cinco escolhas são obrigatórias. [restrictions] vazio sai do JSON:
/// a ausência equivale a lista vazia. Não há campo de texto livre.
final class RecommendationPreferences {
  RecommendationPreferences({
    required this.budget,
    required this.hunger,
    required this.protein,
    required this.style,
    required this.taste,
    List<DietaryRestriction> restrictions = const [],
  }) : restrictions = List.unmodifiable(_inContractOrder(restrictions));

  factory RecommendationPreferences.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'preferences');
      _rejectUnknownKeys(map, _preferenceKeys, 'preferences');
      return RecommendationPreferences(
        budget: MealBudget.parse(readRequiredString(map, 'budget')),
        hunger: MealHunger.parse(readRequiredString(map, 'hunger')),
        protein: MealProtein.parse(readRequiredString(map, 'protein')),
        style: MealStyle.parse(readRequiredString(map, 'style')),
        taste: MealTaste.parse(readRequiredString(map, 'taste')),
        restrictions: _readRestrictions(map),
      );
    });
  }

  final MealBudget budget;
  final MealHunger hunger;
  final MealProtein protein;
  final MealStyle style;
  final MealTaste taste;
  final List<DietaryRestriction> restrictions;

  /// JSON do contrato. Lista vazia omite `restrictions`.
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'budget': budget.value,
      'hunger': hunger.value,
      'protein': protein.value,
      'style': style.value,
      'taste': taste.value,
    };
    if (restrictions.isNotEmpty) {
      json['restrictions'] = [for (final restriction in restrictions) restriction.value];
    }
    return json;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecommendationPreferences &&
        other.budget == budget &&
        other.hunger == hunger &&
        other.protein == protein &&
        other.style == style &&
        other.taste == taste &&
        _sameRestrictions(other.restrictions, restrictions);
  }

  @override
  int get hashCode =>
      Object.hash(budget, hunger, protein, style, taste, Object.hashAll(restrictions));

  @override
  String toString() =>
      'RecommendationPreferences(${budget.value}, ${hunger.value}, ${protein.value}, '
      '${style.value}, ${taste.value}, $restrictions)';
}

List<DietaryRestriction> _inContractOrder(List<DietaryRestriction> restrictions) {
  final selected = restrictions.toSet();
  if (selected.length != restrictions.length) {
    throw ArgumentError.value(restrictions, 'restrictions', 'restrição repetida');
  }
  return [
    for (final restriction in DietaryRestriction.values)
      if (selected.contains(restriction)) restriction,
  ];
}

List<DietaryRestriction> _readRestrictions(Map<String, Object?> json) {
  if (!json.containsKey('restrictions')) return const [];
  final value = json['restrictions'];
  if (value == null) {
    throw ArgumentError.value(value, 'restrictions', 'restrictions nulo');
  }
  if (value is! List) {
    throw ArgumentError.value(value, 'restrictions', 'restrictions deve ser uma lista');
  }
  if (value.length > DietaryRestriction.values.length) {
    throw ArgumentError.value(value, 'restrictions', 'restrictions aceita no máximo 5 itens');
  }

  final parsed = <DietaryRestriction>[];
  for (final item in value) {
    if (item is! String) {
      throw ArgumentError.value(item, 'restrictions', 'restrictions deve ter strings');
    }
    final restriction = DietaryRestriction.parse(item);
    if (parsed.contains(restriction)) {
      throw ArgumentError.value(item, 'restrictions', 'restrição repetida');
    }
    parsed.add(restriction);
  }
  return parsed;
}

bool _sameRestrictions(List<DietaryRestriction> left, List<DietaryRestriction> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _rejectUnknownKeys(Map<String, Object?> json, Set<String> allowed, String name) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw ArgumentError.value(key, name, 'campo desconhecido');
    }
  }
}
