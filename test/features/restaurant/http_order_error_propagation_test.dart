import 'dart:convert';
import 'dart:io';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/features/client/order/order_intent.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/restaurant/http_order_repository.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const key = '00000000-0000-4000-8000-000000000001';
  final items = [CartItem(productId: 'p1', quantity: 2, note: 'sem cebola')];
  final body = OrderRequest.body(table: '12', items: items);

  Future<OrderSubmission> post(
    Future<void> Function(HttpRequest request) respond, {
    String? idempotencyKey = key,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      await respond(request);
    });
    final client = http.Client();
    addTearDown(client.close);
    final repository = HttpOrderRepository(
      ApiClient(
        baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
        timeout: timeout,
        httpClient: client,
      ),
    );
    return repository.create(table: '12', items: items, idempotencyKey: idempotencyKey, body: body);
  }

  void expectBlocked(
    OrderSubmission result, {
    required String message,
    required DataFailure failure,
  }) {
    expect(result.resendBlocked, isTrue);
    expect(result.outcomeUncertain, isFalse);
    expect(result.order, isNull);
    expect(result.shouldClearCart, isFalse);
    expect(result.failure, failure);
    expect(result.message, message);
  }

  void expectUncertain(OrderSubmission result) {
    expect(result.resendBlocked, isFalse);
    expect(result.outcomeUncertain, isTrue);
    expect(result.order, isNull);
    expect(result.shouldClearCart, isFalse);
    expect(result.failure, DataFailure.uncertain);
    expect(result.message, OrderSubmission.uncertainOutcomeMessage);
  }

  test('500 com IDEMPOTENCY_STATE_INVALID válido bloqueia a chave', () async {
    final result = await post((request) async {
      final response = request.response;
      response.statusCode = 500;
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'error': {
            'code': 'IDEMPOTENCY_STATE_INVALID',
            'message': 'A chave de idempotência não possui o pedido correspondente',
          },
        }),
      );
      await response.close();
    });

    expectBlocked(
      result,
      message: OrderSubmission.idempotencyInvalidMessage,
      failure: DataFailure.unavailable,
    );
  });

  test('500 com JSON inválido e chave enviada bloqueia sem inventar o código', () async {
    final result = await post((request) async {
      final response = request.response;
      response.statusCode = 500;
      response.write('not-json');
      await response.close();
    });

    expectBlocked(
      result,
      message: OrderSubmission.unreadableServerErrorMessage,
      failure: DataFailure.unavailable,
    );
    expect(result.detail, isNot(contains('IDEMPOTENCY_STATE_INVALID')));
  });

  test('500 com corpo vazio e chave enviada bloqueia sem inventar o código', () async {
    final result = await post((request) async {
      final response = request.response;
      response.statusCode = 500;
      response.contentLength = 0;
      await response.close();
    });

    expectBlocked(
      result,
      message: OrderSubmission.unreadableServerErrorMessage,
      failure: DataFailure.unavailable,
    );
  });

  test('500 cuja leitura do corpo falha ou estoura o tempo bloqueia a chave', () async {
    final thrown = await post((request) async {
      final response = request.response;
      response.statusCode = 500;
      final socket = await response.detachSocket();
      socket.destroy();
    });
    final timedOut = await post((request) async {
      final response = request.response;
      response.statusCode = 500;
      response.write('{');
      await response.flush();
      await Future<void>.delayed(const Duration(seconds: 2));
      await response.close();
    }, timeout: const Duration(milliseconds: 200));

    expectBlocked(
      thrown,
      message: OrderSubmission.unreadableServerErrorMessage,
      failure: DataFailure.unavailable,
    );
    expectBlocked(
      timedOut,
      message: OrderSubmission.unreadableServerErrorMessage,
      failure: DataFailure.unavailable,
    );
  });

  test('409 sem código utilizável continua bloqueando a chave enviada', () async {
    final result = await post((request) async {
      final response = request.response;
      response.statusCode = 409;
      response.write('not-json');
      await response.close();
    });

    expectBlocked(
      result,
      message: OrderSubmission.idempotencyConflictMessage,
      failure: DataFailure.conflict,
    );
  });

  test('500 com código diferente permanece incerto', () async {
    final result = await post((request) async {
      final response = request.response;
      response.statusCode = 500;
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'error': {'code': 'INTERNAL_ERROR', 'message': 'Erro interno'},
        }),
      );
      await response.close();
    });

    expectUncertain(result);
    expect(result.detail, 'Erro interno');
  });

  test('502 e 503 sem código permanecem incertos', () async {
    Future<OrderSubmission> gateway(int status) {
      return post((request) async {
        final response = request.response;
        response.statusCode = status;
        await response.close();
      });
    }

    expectUncertain(await gateway(502));
    expectUncertain(await gateway(503));
  });

  test('tempo esgotado antes dos headers permanece incerto', () async {
    final result = await post((request) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      await request.response.close();
    }, timeout: const Duration(milliseconds: 200));

    expectUncertain(result);
  });

  test('500 sem código e sem chave não vira bloqueio de idempotência', () async {
    final result = await post((request) async {
      final response = request.response;
      response.statusCode = 500;
      response.write('not-json');
      await response.close();
    }, idempotencyKey: null);

    expectUncertain(result);
  });

  test('bloqueio de 500 sem código não emite outro POST nem outro UUID', () async {
    var calls = 0;
    String? seenKey;
    String? seenBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      calls++;
      seenKey = request.headers.value('idempotency-key');
      seenBody = await utf8.decoder.bind(request).join();
      final response = request.response;
      response.statusCode = 500;
      response.contentLength = 0;
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
    final ids = <String>[];
    final store = MemoryOrderIntentStore();
    final viewModel = OrderSubmissionViewModel(
      repository,
      intentStore: store,
      now: () => DateTime.utc(2026, 11, 1, 12),
      newIntentId: () {
        final id = '00000000-0000-4000-8000-${(ids.length + 1).toString().padLeft(12, '0')}';
        ids.add(id);
        return id;
      },
    );

    await viewModel.submit(table: '12', items: items);
    final captured = viewModel.intentId;

    expect(calls, 1);
    expect(ids, hasLength(1));
    expect(seenKey, ids.single);
    expect(jsonDecode(seenBody!), body);
    expect(viewModel.resendBlocked, isTrue);
    expect(viewModel.outcomeUncertain, isFalse);
    expect(viewModel.canResumeSameIntent, isFalse);
    expect(viewModel.canRequestSubmit, isFalse);
    expect(viewModel.canBeginAnotherOrder, isFalse);
    expect(viewModel.errorMessage, OrderSubmission.unreadableServerErrorMessage);
    expect((await store.load())!.phase, OrderIntentPhase.blocked);

    await viewModel.resume(captured!);
    await viewModel.submit(table: '12', items: items);
    await viewModel.resume(captured);

    expect(calls, 1);
    expect(ids, hasLength(1));
    expect(viewModel.intentId, captured);
    expect(viewModel.errorMessage, OrderSubmission.unreadableServerErrorMessage);
  });

  const created = {
    'id': 'o_550e8400-e29b-41d4-a716-446655440000',
    'table': '12',
    'status': 'received',
    'items': [
      {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
    ],
    'totalCents': 6580,
    'createdAt': '2026-10-25T18:00:00.000Z',
  };

  Map<String, Object?> decodeBody(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('body do pedido inválido');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> writeJson(HttpResponse response, int status, Object? body) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<
    ({
      OrderSubmissionViewModel viewModel,
      MemoryOrderIntentStore store,
      List<String> ids,
      List<String?> keys,
      List<String> bodies,
    })
  >
  openAgainst(Future<void> Function(HttpRequest request) respond) async {
    final keys = <String?>[];
    final bodies = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      keys.add(request.headers.value('idempotency-key'));
      bodies.add(await utf8.decoder.bind(request).join());
      await respond(request);
    });
    final client = http.Client();
    addTearDown(client.close);
    final repository = HttpOrderRepository(
      ApiClient(
        baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
        httpClient: client,
      ),
    );
    final ids = <String>[];
    final store = MemoryOrderIntentStore();
    final viewModel = OrderSubmissionViewModel(
      repository,
      intentStore: store,
      now: () => DateTime.utc(2026, 11, 1, 12),
      newIntentId: () {
        final id = '00000000-0000-4000-8000-${(ids.length + 1).toString().padLeft(12, '0')}';
        ids.add(id);
        return id;
      },
    );
    return (viewModel: viewModel, store: store, ids: ids, keys: keys, bodies: bodies);
  }

  test('400 VALIDATION_ERROR libera outra intenção com o carrinho atual', () async {
    var calls = 0;
    final session = await openAgainst((request) async {
      calls++;
      if (calls == 1) {
        await writeJson(request.response, 400, {
          'error': {'code': 'VALIDATION_ERROR', 'message': 'Quantidade inválida'},
        });
        return;
      }
      await writeJson(request.response, 201, created);
    });

    await session.viewModel.submit(table: '12', items: items);

    expect(session.viewModel.isDefiniteFailure, isTrue);
    expect(session.viewModel.canRequestSubmit, isTrue);
    expect(session.viewModel.outcomeUncertain, isFalse);
    expect(session.viewModel.errorMessage, 'Quantidade inválida');
    expect(session.viewModel.shouldClearCart, isFalse);
    expect(await session.store.load(), isNull);
    expect(decodeBody(session.bodies.single)['items'], [
      {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
    ]);

    final edited = [CartItem(productId: 'p1', quantity: 5, note: 'sem cebola')];
    await session.viewModel.submit(table: '12', items: edited);

    expect(session.ids, hasLength(2));
    expect(session.keys, [session.ids[0], session.ids[1]]);
    expect(session.keys[1], isNot(session.keys[0]));
    expect(decodeBody(session.bodies.last)['items'], [
      {'productId': 'p1', 'quantity': 5, 'note': 'sem cebola'},
    ]);
    expect(session.viewModel.status, OrderSubmissionStatus.succeeded);
    expect(session.viewModel.shouldClearCart, isTrue);
  });

  test('404 PRODUCT_NOT_FOUND libera outra intenção com o carrinho atual', () async {
    var calls = 0;
    final session = await openAgainst((request) async {
      calls++;
      if (calls == 1) {
        await writeJson(request.response, 404, {
          'error': {'code': 'PRODUCT_NOT_FOUND', 'message': 'Produto p1 indisponível'},
        });
        return;
      }
      await writeJson(request.response, 201, created);
    });

    await session.viewModel.submit(table: '12', items: items);

    expect(session.viewModel.isDefiniteFailure, isTrue);
    expect(session.viewModel.failure, DataFailure.notFound);
    expect(session.viewModel.canRequestSubmit, isTrue);
    expect(session.viewModel.shouldClearCart, isFalse);
    expect(await session.store.load(), isNull);

    await session.viewModel.submit(table: '12', items: items);

    expect(session.ids, hasLength(2));
    expect(session.keys[1], isNot(session.keys[0]));
    expect(session.viewModel.order!.id, created['id']);
  });

  test('404 NOT_FOUND preserva a chave e não aceita outro UUID', () async {
    final session = await openAgainst((request) async {
      await writeJson(request.response, 404, {
        'error': {'code': 'NOT_FOUND', 'message': 'Rota não encontrada'},
      });
    });

    await session.viewModel.submit(table: '12', items: items);
    final captured = session.viewModel.intentId;
    final stored = await session.store.load();

    expect(session.viewModel.outcomeUncertain, isTrue);
    expect(session.viewModel.isDefiniteFailure, isFalse);
    expect(session.viewModel.canRequestSubmit, isFalse);
    expect(session.viewModel.canResumeSameIntent, isTrue);
    expect(session.viewModel.resendBlocked, isFalse);
    expect(session.viewModel.shouldClearCart, isFalse);
    expect(stored!.id, captured);
    expect(stored.phase, OrderIntentPhase.uncertain);
    expect(stored.body, body);

    await session.viewModel.submit(
      table: '12',
      items: [CartItem(productId: 'p9', quantity: 1, note: null)],
    );

    expect(session.ids, hasLength(1));
    expect(session.keys, hasLength(1));
    expect(session.viewModel.intentId, captured);

    await session.viewModel.resume(captured!);

    expect(session.ids, hasLength(1));
    expect(session.keys, [captured, captured]);
    expect(decodeBody(session.bodies.last), body);
  });

  test('400 com outro código e corpo ilegível em 400 ou 404 preservam a chave', () async {
    Future<OrderSubmission> classified(int status, Object? payload) {
      return post((request) async {
        final response = request.response;
        response.statusCode = status;
        if (payload is String) {
          response.write(payload);
        } else {
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(payload));
        }
        await response.close();
      });
    }

    final other = await classified(400, {
      'error': {'code': 'X', 'message': 'fora do contrato'},
    });
    final blank400 = await classified(400, 'not-json');
    final blank404 = await classified(404, 'not-json');
    final notFound = await classified(404, {
      'error': {'code': 'NOT_FOUND', 'message': 'Rota não encontrada'},
    });

    for (final result in [other, blank400, blank404, notFound]) {
      expect(result.outcomeUncertain, isTrue);
      expect(result.resendBlocked, isFalse);
      expect(result.shouldClearCart, isFalse);
      expect(result.failure, DataFailure.uncertain);
      expect(result.message, OrderSubmission.uncertainOutcomeMessage);
    }
  });

  test('erro depois dos headers em 404 não libera outra chave', () async {
    final session = await openAgainst((request) async {
      final response = request.response;
      response.statusCode = 404;
      final socket = await response.detachSocket();
      socket.destroy();
    });

    await session.viewModel.submit(table: '12', items: items);
    await session.viewModel.submit(table: '12', items: items);

    expect(session.ids, hasLength(1));
    expect(session.keys, hasLength(1));
    expect(session.keys.single, session.ids.single);
    expect(session.viewModel.outcomeUncertain, isTrue);
    expect(session.viewModel.canRequestSubmit, isFalse);
    expect(session.viewModel.resendBlocked, isFalse);
    expect((await session.store.load())!.id, session.ids.single);
    expect(session.viewModel.shouldClearCart, isFalse);
  });
}
