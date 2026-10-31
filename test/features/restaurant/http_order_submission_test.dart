import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/features/restaurant/http_order_repository.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Resposta de `POST /orders` no contrato aceito da dinna-api.
const _created = {
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

final _items = [
  CartItem(productId: 'p1', quantity: 2, note: 'sem cebola'),
  CartItem(productId: 'p2', quantity: 1, note: null),
];

void main() {
  final baseUrl = Uri.parse('http://localhost:3333');

  HttpOrderRepository repositoryReturning(http.Response response) {
    return HttpOrderRepository(
      ApiClient(baseUrl: baseUrl, httpClient: MockClient((_) async => response)),
    );
  }

  test('a frase de incerteza do client é a do contrato de envio', () {
    expect(ApiClient.uncertainOutcomeMessage, OrderSubmission.uncertainOutcomeMessage);
  });

  test('envia mesa, vários itens e observação e lê o pedido do 201', () async {
    late http.Request requested;
    var calls = 0;
    final repository = HttpOrderRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          calls++;
          requested = request;
          return http.Response(
            jsonEncode(_created),
            201,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await repository.create(table: '12', items: _items);
    final order = result.order!;

    expect(calls, 1);
    expect(requested.method, 'POST');
    expect(requested.url.toString(), 'http://localhost:3333/orders');
    expect(requested.url.query, isEmpty);
    expect(requested.headers['content-type'], 'application/json');
    expect(requested.headers['accept'], 'application/json');
    expect(jsonDecode(requested.body), {
      'table': '12',
      'items': [
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
        {'productId': 'p2', 'quantity': 1},
      ],
    });
    expect(requested.body, isNot(contains('totalCents')));
    expect(requested.body, isNot(contains('createdAt')));
    expect(requested.body, isNot(contains('"status"')));
    expect(result.message, isNull);
    expect(result.failure, isNull);
    expect(result.detail, isNull);
    expect(result.outcomeUncertain, isFalse);
    expect(result.shouldClearCart, isTrue);
    expect(order.id, 'o_550e8400-e29b-41d4-a716-446655440000');
    expect(order.table, '12');
    expect(order.status, OrderStatus.received);
    expect(order.items.map((item) => item.productId), ['p1', 'p2']);
    expect(order.items.first.quantity, 2);
    expect(order.items.first.note, 'sem cebola');
    expect(order.items.last.quantity, 1);
    expect(order.items.last.note, isNull);
    expect(order.totalCents, 10470);
    expect(order.createdAt, DateTime.utc(2026, 10, 25, 18));
    expect(order.createdAt.isUtc, isTrue);
  });

  test('recusa mesa vazia, lista vazia e identificador em branco sem chamar a API', () async {
    var calls = 0;
    final repository = HttpOrderRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 500);
        }),
      ),
    );

    final emptyTable = await repository.create(table: '', items: [_items.first]);
    final blankTable = await repository.create(table: '   ', items: [_items.first]);
    final emptyItems = await repository.create(table: '12', items: const <CartItem>[]);
    final blankId = await repository.create(
      table: '12',
      items: [CartItem(productId: '   ', quantity: 1, note: null)],
    );

    expect(calls, 0);
    expect(emptyTable.order, isNull);
    expect(emptyTable.failure, DataFailure.validation);
    expect(emptyTable.outcomeUncertain, isFalse);
    expect(emptyTable.shouldClearCart, isFalse);
    expect(emptyTable.message, HttpOrderRepository.emptyTableMessage);
    expect(blankTable.message, HttpOrderRepository.emptyTableMessage);
    expect(emptyItems.message, HttpOrderRepository.emptyItemsMessage);
    expect(emptyItems.failure, DataFailure.validation);
    expect(blankId.message, HttpOrderRepository.invalidItemMessage);
    expect(blankId.failure, DataFailure.validation);
    expect(() => CartItem(productId: 'p1', quantity: 0, note: null), throwsArgumentError);
    expect(() => CartItem(productId: '', quantity: 1, note: null), throwsArgumentError);
  });

  test('traduz 400, 404, 409 e 500 como falha confirmada', () async {
    Future<OrderSubmission> failed(int status, String message) {
      return repositoryReturning(
        http.Response(
          jsonEncode({
            'error': {'code': 'X', 'message': message},
          }),
          status,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ).create(table: '12', items: _items);
    }

    final validation = await failed(400, 'Mesa inválida');
    final missing = await failed(404, 'Produto p9 não encontrado ou indisponível');
    final conflict = await failed(409, 'Pedido em conflito');
    final server = await failed(500, 'Erro interno');
    final bare = await repositoryReturning(
      http.Response('{}', 500, headers: const {'content-type': 'application/json'}),
    ).create(table: '12', items: _items);

    expect(validation.message, 'Mesa inválida');
    expect(validation.failure, DataFailure.validation);
    expect(missing.message, 'Produto p9 não encontrado ou indisponível');
    expect(missing.failure, DataFailure.notFound);
    expect(conflict.message, 'Pedido em conflito');
    expect(conflict.failure, DataFailure.conflict);
    expect(server.message, 'Erro interno');
    expect(server.failure, DataFailure.unavailable);
    expect(bare.message, ApiClient.httpFailureMessage);
    expect(bare.detail, 'HTTP 500');
    expect(bare.failure, DataFailure.unavailable);

    for (final result in [validation, missing, conflict, server, bare]) {
      expect(result.order, isNull);
      expect(result.outcomeUncertain, isFalse);
      expect(result.shouldClearCart, isFalse);
      expect(result.message, isNot(contains('pode ter sido registrado')));
    }
  });

  test('JSON inválido em 201 não afirma que o pedido falhou', () async {
    final notJson = await repositoryReturning(http.Response('not-json', 201))
        .create(table: '12', items: _items);
    final empty = await repositoryReturning(http.Response('', 201))
        .create(table: '12', items: _items);
    final missingFields = await repositoryReturning(
      http.Response(
        jsonEncode({'ok': true}),
        201,
        headers: const {'content-type': 'application/json'},
      ),
    ).create(table: '12', items: _items);
    final errorBody = await repositoryReturning(http.Response('not-json', 500))
        .create(table: '12', items: _items);

    for (final result in [notJson, empty, missingFields]) {
      expect(result.order, isNull);
      expect(result.outcomeUncertain, isTrue);
      expect(result.failure, DataFailure.uncertain);
      expect(result.shouldClearCart, isFalse);
      expect(result.message, OrderSubmission.uncertainOutcomeMessage);
      expect(result.message, isNot(contains('não foi criado')));
      expect(result.message, isNot(contains('falhou')));
    }
    expect(notJson.detail, 'Resposta inválida da API');

    expect(errorBody.outcomeUncertain, isFalse);
    expect(errorBody.failure, DataFailure.unavailable);
    expect(errorBody.message, ApiClient.httpFailureMessage);
    expect(errorBody.detail, 'HTTP 500: corpo inválido');
    expect(errorBody.shouldClearCart, isFalse);
  });

  test('falha de conexão antes da resposta não é resultado incerto', () async {
    final repository = HttpOrderRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async => throw const SocketException('Connection refused')),
      ),
    );

    final result = await repository.create(table: '12', items: _items);

    expect(result.order, isNull);
    expect(result.outcomeUncertain, isFalse);
    expect(result.failure, DataFailure.unavailable);
    expect(result.shouldClearCart, isFalse);
    expect(result.message, 'Não foi possível conectar à API');
    expect(result.message, isNot(contains('Connection refused')));
    expect(result.message, isNot(contains('pode ter sido registrado')));
    expect(result.detail, 'Connection refused');
  });

  test('tempo esgotado depois do envio é incerto e não repete o POST', () async {
    var calls = 0;
    late http.Request requested;
    final repository = HttpOrderRepository(
      ApiClient(
        baseUrl: baseUrl,
        timeout: const Duration(milliseconds: 30),
        httpClient: MockClient((request) {
          calls++;
          requested = request;
          return Completer<http.Response>().future;
        }),
      ),
    );

    final result = await repository.create(table: '12', items: _items);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(calls, 1);
    expect(requested.method, 'POST');
    expect(jsonDecode(requested.body), {
      'table': '12',
      'items': [
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
        {'productId': 'p2', 'quantity': 1},
      ],
    });
    expect(result.order, isNull);
    expect(result.outcomeUncertain, isTrue);
    expect(result.failure, DataFailure.uncertain);
    expect(result.shouldClearCart, isFalse);
    expect(result.message, OrderSubmission.uncertainOutcomeMessage);
  });

  test('queda de conexão depois do envio é incerta e não repete o POST', () async {
    final transport = _ResetAfterSend();
    final repository = HttpOrderRepository(ApiClient(baseUrl: baseUrl, httpClient: transport));

    final result = await repository.create(table: '12', items: _items);

    expect(transport.calls, 1);
    expect(result.order, isNull);
    expect(result.outcomeUncertain, isTrue);
    expect(result.failure, DataFailure.uncertain);
    expect(result.shouldClearCart, isFalse);
    expect(result.message, OrderSubmission.uncertainOutcomeMessage);
    expect(result.message, isNot(contains('Connection reset')));
    expect(result.detail, 'Connection reset by peer');
  });
}

class _ResetAfterSend extends http.BaseClient {
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream<List<int>>.error(const SocketException('Connection reset by peer')),
      201,
    );
  }
}
