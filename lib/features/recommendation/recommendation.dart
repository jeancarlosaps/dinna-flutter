import '../../core/domain/json_values.dart';

/// Quem produziu a lista. Falha do provedor com fallback continua [unavailable].
enum RecommendationProvider {
  answered('answered'),
  unavailable('unavailable'),
  notCalled('not_called');

  const RecommendationProvider(this.value);

  final String value;

  static RecommendationProvider parse(String raw) {
    for (final provider in RecommendationProvider.values) {
      if (provider.value == raw) return provider;
    }
    throw FormatException('provider desconhecido: $raw');
  }
}

/// Resultado da seleção. Lista vazia só com os dois outcomes sem sugestão.
enum RecommendationOutcome {
  suggestions('suggestions'),
  noCompatibleProducts('no_compatible_products'),
  emptyCatalog('empty_catalog');

  const RecommendationOutcome(this.value);

  final String value;

  static RecommendationOutcome parse(String raw) {
    for (final outcome in RecommendationOutcome.values) {
      if (outcome.value == raw) return outcome;
    }
    throw FormatException('outcome desconhecido: $raw');
  }
}

const _responseKeys = {'provider', 'outcome', 'products'};
const _suggestionKeys = {'productId', 'reason'};

/// Um prato sugerido. A API manda o id e o motivo, sem nome, preço ou imagem.
final class RecommendationSuggestion {
  RecommendationSuggestion({required this.productId, required this.reason}) {
    if (productId.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'productId deve ter ao menos 1 caractere');
    }
    if (reason.isEmpty || reason.length > 80) {
      throw ArgumentError.value(reason, 'reason', 'reason deve ter de 1 a 80 caracteres');
    }
  }

  factory RecommendationSuggestion.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'products');
      _rejectUnknownKeys(map, _suggestionKeys, 'products');
      return RecommendationSuggestion(
        productId: readRequiredString(map, 'productId'),
        reason: readRequiredString(map, 'reason', maxLength: 80),
      );
    });
  }

  final String productId;
  final String reason;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecommendationSuggestion &&
        other.productId == productId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(productId, reason);

  @override
  String toString() => 'RecommendationSuggestion($productId, $reason)';
}

/// Resposta 200 de `POST /ai/recommendation`.
///
/// Só os quatro pares do contrato passam. Outra combinação, id repetido ou
/// lista fora do outcome é erro de parsing, não uma sugestão.
final class Recommendation {
  Recommendation({
    required this.provider,
    required this.outcome,
    required List<RecommendationSuggestion> products,
  }) : products = List.unmodifiable(products) {
    if (!_validPair(provider, outcome)) {
      throw ArgumentError('combinação inválida de provider e outcome');
    }
    final ids = products.map((product) => product.productId).toSet();
    if (ids.length != products.length) {
      throw ArgumentError('productId repetido');
    }
    switch (outcome) {
      case RecommendationOutcome.suggestions:
        if (products.isEmpty || products.length > 3) {
          throw ArgumentError('suggestions traz de 1 a 3 pratos');
        }
      case RecommendationOutcome.noCompatibleProducts:
      case RecommendationOutcome.emptyCatalog:
        if (products.isNotEmpty) {
          throw ArgumentError('outcome sem sugestão traz products vazio');
        }
    }
  }

  factory Recommendation.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'Recommendation');
      _rejectUnknownKeys(map, _responseKeys, 'Recommendation');
      final products = readRequiredList(
        map,
        'products',
        RecommendationSuggestion.fromJson,
        minLength: 0,
      );
      return Recommendation(
        provider: RecommendationProvider.parse(readRequiredString(map, 'provider')),
        outcome: RecommendationOutcome.parse(readRequiredString(map, 'outcome')),
        products: products,
      );
    });
  }

  final RecommendationProvider provider;
  final RecommendationOutcome outcome;
  final List<RecommendationSuggestion> products;

  /// Fallback concluído: houve sugestão e o provedor não respondeu.
  bool get usedFallback =>
      provider == RecommendationProvider.unavailable &&
      outcome == RecommendationOutcome.suggestions;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Recommendation &&
        other.provider == provider &&
        other.outcome == outcome &&
        _sameProducts(other.products, products);
  }

  @override
  int get hashCode => Object.hash(provider, outcome, Object.hashAll(products));

  @override
  String toString() => 'Recommendation(${provider.value}, ${outcome.value}, $products)';
}

bool _validPair(RecommendationProvider provider, RecommendationOutcome outcome) {
  return switch ((provider, outcome)) {
    (RecommendationProvider.answered, RecommendationOutcome.suggestions) => true,
    (RecommendationProvider.unavailable, RecommendationOutcome.suggestions) => true,
    (RecommendationProvider.notCalled, RecommendationOutcome.noCompatibleProducts) => true,
    (RecommendationProvider.notCalled, RecommendationOutcome.emptyCatalog) => true,
    _ => false,
  };
}

bool _sameProducts(List<RecommendationSuggestion> left, List<RecommendationSuggestion> right) {
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
