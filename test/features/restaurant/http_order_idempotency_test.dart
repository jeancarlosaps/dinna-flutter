import 'dart:convert';
import 'dart:io';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/restaurant/http_order_repository.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const created = {
    'id': 'o_550e8400-e29b-41d4-a716-446655440000',
    'table': '12',
    'status': 'received',
    'items': [
      {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
      {'productId': 'p2', 'quantity': 1},
    ],
    'totalCents': 10470,
    'createdAt': '2026-10-25T18:00:00.000Z',
  };

  final items = [
    CartItem(productId: 'p1', quantity: 2, note: 'sem cebola'),
    CartItem(productId: 'p2', quantity: 1, note: null),
  ];

  test('servidor local repete o 201 e responde 409 no payload diferente', () async {
    final requests = <({String? key, String body})>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final key = request.headers.value('idempotency-key');
      requests.add((key: key, body: body));
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (key == null) {
        response.statusCode = 400;
        response.write(
          jsonEncode({
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'O header Idempotency-Key deve ser um UUID',
            },
          }),
        );
      } else if (requests.where((call) => call.key == key).length == 1 ||
          requests.firstWhere((call) => call.key == key).body == body) {
        response.statusCode = 201;
        response.write(jsonEncode(created));
      } else {
        response.statusCode = 409;
        response.write(
          jsonEncode({
            'error': {
              'code': 'IDEMPOTENCY_KEY_CONFLICT',
              'message': 'A Idempotency-Key já foi usada com um payload diferente',
            },
          }),
        );
      }
      await response.close();
    });

    final client = http.Client();
    addTearDown(client.close);
    final repository = HttpOrderRepository(
      ApiClient(
        baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
        httpClient: client,
      ),
    );
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileOrderIntentStore(File('${directory.path}/order-intent.json'));
    final now = DateTime.utc(2026, 11, 1, 12);
    final first = OrderSubmissionViewModel(repository, intentStore: store, now: () => now);

    await first.submit(table: '12', items: items);

    expect(requests, hasLength(1));
    expect(requests.single.key, first.intentId);
    expect(jsonDecode(requests.single.body), {
      'table': '12',
      'items': [
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
        {'productId': 'p2', 'quantity': 1},
      ],
    });
    expect(first.status, OrderSubmissionStatus.succeeded);
    expect(first.order!.id, created['id']);
    expect(first.shouldClearCart, isTrue);

    final restarted = OrderSubmissionViewModel(repository, intentStore: store, now: () => now);
    await restarted.restore();

    expect(requests, hasLength(1));
    expect(restarted.status, OrderSubmissionStatus.succeeded);
    expect(restarted.order!.id, created['id']);
    expect(restarted.canRequestSubmit, isFalse);

    final replay = await repository.create(
      table: '12',
      items: items,
      idempotencyKey: first.intentId,
      body: {
        'table': '12',
        'items': [
          {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
          {'productId': 'p2', 'quantity': 1},
        ],
      },
    );
    final conflict = await repository.create(
      table: '12',
      items: [CartItem(productId: 'p1', quantity: 1, note: '')],
      idempotencyKey: first.intentId,
      body: {
        'table': '12',
        'items': [
          {'productId': 'p1', 'quantity': 1, 'note': ''},
        ],
      },
    );

    expect(replay.order!.id, created['id']);
    expect(replay.shouldClearCart, isTrue);
    expect(conflict.resendBlocked, isTrue);
    expect(conflict.failure, DataFailure.conflict);
    expect(conflict.message, OrderSubmission.idempotencyConflictMessage);
    expect(conflict.shouldClearCart, isFalse);
    expect(requests, hasLength(3));
    expect(requests[1].key, requests.first.key);
    expect(requests[1].body, requests.first.body);
    expect(requests[2].key, requests.first.key);
    expect(requests[2].body, isNot(requests.first.body));
  });
}
