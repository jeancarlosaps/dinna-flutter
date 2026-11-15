import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

const _reason = 'Carne, R\$ 36–60, Salgado, sem cebola na lista cadastrada';

void main() {
  test('lê os quatro pares válidos', () {
    final answered = Recommendation.fromJson({
      'provider': 'answered',
      'outcome': 'suggestions',
      'products': [
        {'productId': 'p2', 'reason': _reason},
      ],
    });
    expect(answered.provider, RecommendationProvider.answered);
    expect(answered.outcome, RecommendationOutcome.suggestions);
    expect(answered.usedFallback, isFalse);
    expect(answered.products.single.productId, 'p2');
    expect(answered.products.single.reason, _reason);

    final fallback = Recommendation.fromJson({
      'provider': 'unavailable',
      'outcome': 'suggestions',
      'products': [
        {'productId': 'p2', 'reason': _reason},
        {'productId': 'p1', 'reason': 'Carne, Salgado'},
      ],
    });
    expect(fallback.usedFallback, isTrue);
    expect(fallback.products.map((item) => item.productId), ['p2', 'p1']);

    final incompatible = Recommendation.fromJson({
      'provider': 'not_called',
      'outcome': 'no_compatible_products',
      'products': [],
    });
    expect(incompatible.provider, RecommendationProvider.notCalled);
    expect(incompatible.outcome, RecommendationOutcome.noCompatibleProducts);
    expect(incompatible.products, isEmpty);
    expect(incompatible.usedFallback, isFalse);

    final emptyCatalog = Recommendation.fromJson({
      'provider': 'not_called',
      'outcome': 'empty_catalog',
      'products': [],
    });
    expect(emptyCatalog.outcome, RecommendationOutcome.emptyCatalog);
    expect(emptyCatalog.products, isEmpty);
  });

  test('rejeita par desconhecido, campo extra e lista incoerente', () {
    expect(
      () => Recommendation.fromJson({
        'provider': 'answered',
        'outcome': 'no_compatible_products',
        'products': [],
      }),
      throwsFormatException,
    );
    expect(
      () => Recommendation.fromJson({
        'provider': 'gemini',
        'outcome': 'suggestions',
        'products': [
          {'productId': 'p2', 'reason': 'Carne'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => Recommendation.fromJson({
        'provider': 'answered',
        'outcome': 'suggestions',
        'products': [
          {'productId': 'p2', 'reason': 'Carne'},
        ],
        'fallback': true,
      }),
      throwsFormatException,
    );
    expect(
      () => Recommendation.fromJson({
        'provider': 'answered',
        'outcome': 'suggestions',
        'products': [],
      }),
      throwsFormatException,
    );
    expect(
      () => Recommendation.fromJson({
        'provider': 'not_called',
        'outcome': 'empty_catalog',
        'products': [
          {'productId': 'p1', 'reason': 'Carne'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => Recommendation.fromJson({
        'provider': 'answered',
        'outcome': 'suggestions',
        'products': [
          {'productId': 'p2', 'reason': 'Carne'},
          {'productId': 'p2', 'reason': 'Carne de novo'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => Recommendation.fromJson({
        'provider': 'unavailable',
        'outcome': 'suggestions',
        'products': [
          {'productId': 'p2', 'reason': 'Carne', 'priceCents': 3890},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => Recommendation.fromJson({'provider': 'answered', 'outcome': 'suggestions'}),
      throwsFormatException,
    );
  });
}
