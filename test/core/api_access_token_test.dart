import 'dart:convert';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/core/network/api_exception.dart';
import 'package:dinna/features/client/cart/cart_repository.dart';
import 'package:dinna/features/client/cart/cart_session.dart';
import 'package:dinna/features/client/order/order_intent.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/menu/http_product_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/recommendation/http_recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_preferences_store.dart';
import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_view_model.dart';
import 'package:dinna/features/restaurant/http_order_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../features/menu/fake_product_repository.dart';

void main() {
  const token = 'token-de-teste';
  const intentId = '00000000-0000-4000-8000-0000000000aa';
  final baseUrl = Uri.parse('http://localhost:3333');
  final unauthorizedBody = jsonEncode({
    'error': {'code': 'UNAUTHORIZED', 'message': 'Token de acesso ausente ou inválido'},
  });

  String? header(http.Request request, String name) {
    final wanted = name.toLowerCase();
    for (final entry in request.headers.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  ApiClient client({
    String? apiToken,
    required Future<http.Response> Function(http.Request request) handler,
  }) {
    return ApiClient(baseUrl: baseUrl, apiToken: apiToken, httpClient: MockClient(handler));
  }

  test('token ausente, vazio ou em branco não envia o header', () async {
    Future<void> expectOmitted(String? apiToken) async {
      late http.Request sent;
      final api = client(
        apiToken: apiToken,
        handler: (request) async {
          sent = request;
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        },
      );

      await api.getJson('/health');

      expect(header(sent, ApiClient.accessTokenHeader), isNull);
      expect(sent.url.toString(), 'http://localhost:3333/health');
    }

    await expectOmitted(null);
    await expectOmitted('');
    await expectOmitted('   ');
  });

  test('GET e POST com token preservam URL, body e headers já definidos', () async {
    final seen = <http.Request>[];
    final api = client(
      apiToken: '  $token  ',
      handler: (request) async {
        seen.add(request);
        return http.Response(jsonEncode({'ok': true}), request.method == 'POST' ? 201 : 200);
      },
    );
    const idempotencyKey = '00000000-0000-4000-8000-000000000001';
    final payload = {
      'table': '12',
      'items': [
        {'productId': 'p1', 'quantity': 1},
      ],
    };

    await api.getJson('/products');
    await api.postJson(
      '/orders',
      payload,
      headers: const {
        'Idempotency-Key': idempotencyKey,
        'X-Custom-Trace': 'mesa-12',
        'Content-Type': 'application/json',
      },
    );

    expect(seen, hasLength(2));
    expect(seen[0].method, 'GET');
    expect(seen[0].url.toString(), 'http://localhost:3333/products');
    expect(header(seen[0], 'Accept'), 'application/json');
    expect(header(seen[0], ApiClient.accessTokenHeader), token);

    expect(seen[1].method, 'POST');
    expect(seen[1].url.toString(), 'http://localhost:3333/orders');
    expect(jsonDecode(seen[1].body), payload);
    expect(header(seen[1], 'Content-Type'), 'application/json');
    expect(header(seen[1], 'Accept'), 'application/json');
    expect(header(seen[1], 'Idempotency-Key'), idempotencyKey);
    expect(header(seen[1], 'X-Custom-Trace'), 'mesa-12');
    expect(header(seen[1], ApiClient.accessTokenHeader), token);
    expect(seen[1].body, isNot(contains(token)));
  });

  test('token configurado não substitui o header informado pelo repositório', () async {
    late http.Request sent;
    final api = client(
      apiToken: token,
      handler: (request) async {
        sent = request;
        return http.Response(jsonEncode({'ok': true}), 201);
      },
    );

    await api.postJson(
      '/orders',
      const {'table': '12'},
      headers: const {ApiClient.accessTokenHeader: 'token-do-repositorio'},
    );

    expect(header(sent, ApiClient.accessTokenHeader), 'token-do-repositorio');
    expect(sent.url.toString(), 'http://localhost:3333/orders');
    expect(jsonDecode(sent.body), {'table': '12'});
  });

  test('HTTP 401 vira falha confirmada, sem repetir e sem o token na exceção', () async {
    Future<ApiException> read(String method) async {
      var calls = 0;
      final api = client(
        apiToken: token,
        handler: (request) async {
          calls++;
          expect(header(request, ApiClient.accessTokenHeader), token);
          expect(request.method, method);
          return http.Response(
            unauthorizedBody,
            401,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        },
      );
      try {
        if (method == 'GET') {
          await api.getJson('/orders');
        } else {
          await api.postJson(
            '/orders',
            const {'table': '12'},
            headers: const {'Idempotency-Key': intentId},
          );
        }
      } on ApiException catch (error) {
        expect(calls, 1);
        return error;
      }
      fail('HTTP 401 deveria falhar');
    }

    final getFailure = await read('GET');
    final postFailure = await read('POST');

    for (final error in [getFailure, postFailure]) {
      expect(error.statusCode, 401);
      expect(error.code, 'UNAUTHORIZED');
      expect(error.message, 'Token de acesso ausente ou inválido');
      expect(error.failure, DataFailure.unavailable);
      expect(error.failure, isNot(DataFailure.notFound));
      expect(error.outcomeUncertain, isFalse);
      expect(error.toString(), isNot(contains(token)));
    }
  });

  test('HTTP 401 não esvazia cardápio nem fila e não apaga dados locais', () async {
    final calls = <http.Request>[];
    http.Response unauthorized(http.Request request) {
      calls.add(request);
      return http.Response(
        unauthorizedBody,
        401,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }

    final api = client(apiToken: token, handler: (request) async => unauthorized(request));
    final products = await HttpProductRepository(api).list();
    final orders = await HttpOrderRepository(api).list();

    expect(products.products, isNull);
    expect(products.failure, DataFailure.unavailable);
    expect(products.failure, isNot(DataFailure.notFound));
    expect(products.message, 'Token de acesso ausente ou inválido');
    expect(orders.orders, isNull);
    expect(orders.failure, DataFailure.unavailable);
    expect(orders.message, 'Token de acesso ausente ou inválido');

    final cart = _RecordingCartRepository([
      CartItem(lineId: 'line-1', productId: 'p1', quantity: 2, note: 'sem cebola'),
    ]);
    final session = CartSession(cart);
    await session.restore();
    final before = session.read();

    final store = MemoryOrderIntentStore();
    final submission = OrderSubmissionViewModel(
      HttpOrderRepository(api),
      intentStore: store,
      newIntentId: () => intentId,
    );
    await submission.submit(table: '12', items: before);

    final persisted = await store.load();
    expect(persisted, isNotNull);
    expect(persisted!.id, intentId);
    expect(persisted.phase, OrderIntentPhase.uncertain);
    expect(persisted.table, '12');
    expect(persisted.items, isNotEmpty);
    expect(submission.shouldClearCart, isFalse);
    expect(submission.outcomeUncertain, isTrue);
    expect(submission.intentId, intentId);
    expect(session.read(), before);
    expect(cart.removals, 0);
    expect(cart.confirmedRemovals, 0);
    expect(await cart.load(), before);

    final orderCalls = calls.where((request) => request.url.path == '/orders');
    final post = orderCalls.singleWhere((request) => request.method == 'POST');
    expect(orderCalls.where((request) => request.method == 'POST'), hasLength(1));
    expect(header(post, 'Idempotency-Key'), intentId);
    expect(header(post, ApiClient.accessTokenHeader), token);
    expect(post.body, isNot(contains(token)));

    final selection = RecommendationSelection(
      budget: MealBudget.from36To60,
      hunger: MealHunger.normal,
      protein: MealProtein.beef,
      style: MealStyle.balanced,
      taste: MealTaste.savory,
      restrictions: const [DietaryRestriction.noOnion],
    );
    final preferences = MemoryRecommendationPreferencesStore(initial: selection);
    final recommendation = RecommendationViewModel(
      HttpRecommendationRepository(api),
      products: FakeProductRepository(() async => ProductList.ready(const [])),
      preferencesStore: preferences,
      cartSession: session,
      table: '12',
    );

    expect(recommendation.canSubmit, isTrue);
    await recommendation.submit();

    expect(recommendation.failure, RecommendationFailure.unavailable);
    expect(preferences.current, selection);
    expect(preferences.current!.isEmpty, isFalse);
    expect(session.read(), before);
    final stillThere = await store.load();
    expect(stillThere?.id, persisted.id);
    expect(stillThere?.phase, OrderIntentPhase.uncertain);
  });
}

class _RecordingCartRepository implements CartRepository {
  _RecordingCartRepository(this.items);

  List<CartItem> items;
  var removals = 0;
  var confirmedRemovals = 0;

  @override
  Future<List<CartItem>> load() async => List<CartItem>.of(items);

  @override
  Future<CartItem> add({required String productId, required int quantity, String? note}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> update(CartItem item) {
    throw UnimplementedError();
  }

  @override
  Future<bool> remove(String lineId) async {
    removals++;
    items = items.where((item) => item.lineId != lineId).toList();
    return true;
  }

  @override
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) async {
    confirmedRemovals++;
    return List<CartItem>.of(items);
  }
}
