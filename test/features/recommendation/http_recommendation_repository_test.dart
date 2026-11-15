import 'dart:convert';
import 'dart:io';

import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/features/recommendation/http_recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final baseUrl = Uri.parse('http://localhost:3333');

  HttpRecommendationRepository repositoryWith(MockClient client) {
    return HttpRecommendationRepository(ApiClient(baseUrl: baseUrl, httpClient: client));
  }

  test('envia o body e lê sugestão 200', () async {
    late http.Request sent;
    final repository = repositoryWith(
      MockClient((request) async {
        sent = request;
        return _json(200, {
          'provider': 'answered',
          'outcome': 'suggestions',
          'products': [
            {'productId': 'p2', 'reason': 'Carne, R\$ 36–60, Salgado'},
          ],
        });
      }),
    );

    final result = await repository.recommend(_request());

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://localhost:3333/ai/recommendation');
    expect(sent.headers['content-type'], 'application/json');
    expect(jsonDecode(sent.body), _request().toJson());
    expect(result.failure, isNull);
    expect(result.recommendation!.provider, RecommendationProvider.answered);
    expect(result.recommendation!.products.single.productId, 'p2');
  });

  test('200 com provedor indisponível é fallback, não erro', () async {
    final repository = repositoryWith(
      MockClient(
        (_) async => _json(200, {
          'provider': 'unavailable',
          'outcome': 'suggestions',
          'products': [
            {'productId': 'p2', 'reason': 'Carne, Salgado'},
          ],
        }),
      ),
    );

    final result = await repository.recommend(_request());

    expect(result.failure, isNull);
    expect(result.recommendation!.usedFallback, isTrue);
    expect(result.recommendation!.products.single.productId, 'p2');
  });

  test('200 sem compatíveis e cardápio vazio permanecem sucesso', () async {
    final incompatible = await repositoryWith(
      MockClient(
        (_) async => _json(200, {
          'provider': 'not_called',
          'outcome': 'no_compatible_products',
          'products': [],
        }),
      ),
    ).recommend(_request());
    final empty = await repositoryWith(
      MockClient(
        (_) async =>
            _json(200, {'provider': 'not_called', 'outcome': 'empty_catalog', 'products': []}),
      ),
    ).recommend(_request());

    expect(incompatible.failure, isNull);
    expect(incompatible.recommendation!.outcome, RecommendationOutcome.noCompatibleProducts);
    expect(empty.failure, isNull);
    expect(empty.recommendation!.outcome, RecommendationOutcome.emptyCatalog);
  });

  test('400 é validação e 500 é indisponibilidade, com texto da recomendação', () async {
    final invalid = await repositoryWith(
      MockClient(
        (_) async => _json(400, {
          'error': {'code': 'VALIDATION_ERROR', 'message': 'Campo protein é inválido'},
        }),
      ),
    ).recommend(_request());
    final internal = await repositoryWith(
      MockClient(
        (_) async => _json(500, {
          'error': {'code': 'INTERNAL_ERROR', 'message': 'Erro interno'},
        }),
      ),
    ).recommend(_request());

    expect(invalid.recommendation, isNull);
    expect(invalid.failure, RecommendationFailure.validation);
    expect(internal.recommendation, isNull);
    expect(internal.failure, RecommendationFailure.unavailable);
    for (final result in [invalid, internal]) {
      expect(result.title, RecommendationRepository.failureTitle);
      expect(result.message, RecommendationRepository.failureMessage);
      expect(result.title, isNot(contains('pode ter sido registrado')));
      expect(result.message, isNot(contains('pode ter sido registrado')));
      expect(result.message, isNot(contains('Campo protein')));
      expect(result.message, isNot(contains('Erro interno')));
    }
  });

  test('JSON inválido e par fora do contrato não viram sucesso', () async {
    final broken = await repositoryWith(MockClient((_) async => http.Response('nao-json', 200)))
        .recommend(_request());
    final pair = await repositoryWith(
      MockClient(
        (_) async =>
            _json(200, {'provider': 'answered', 'outcome': 'empty_catalog', 'products': []}),
      ),
    ).recommend(_request());

    expect(broken.recommendation, isNull);
    expect(broken.failure, RecommendationFailure.unavailable);
    expect(pair.recommendation, isNull);
    expect(pair.failure, RecommendationFailure.unavailable);
    expect(broken.title, isNot(ApiClient.uncertainOutcomeMessage));
    expect(broken.message, isNot(contains('pode ter sido registrado')));
  });

  test('falha de transporte não usa a mensagem de pedido registrado', () async {
    final repository = repositoryWith(
      MockClient((_) async => throw const SocketException('offline')),
    );

    final result = await repository.recommend(_request());

    expect(result.recommendation, isNull);
    expect(result.failure, RecommendationFailure.unavailable);
    expect(result.title, RecommendationRepository.failureTitle);
    expect(result.message, RecommendationRepository.failureMessage);
    expect(result.title, isNot(ApiClient.uncertainOutcomeMessage));
    expect('${result.title} ${result.message}', isNot(contains('pode ter sido registrado')));
  });
}

http.Response _json(int status, Object body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

RecommendationRequest _request() {
  return RecommendationRequest(
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
}
