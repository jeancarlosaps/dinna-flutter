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
}
