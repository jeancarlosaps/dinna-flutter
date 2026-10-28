import 'dart:convert';
import 'dart:io';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/features/restaurant/http_order_repository.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Exemplo de `Order` no contrato, com e sem milissegundos, como a API emite.
const _older = {
  'id': 'o1',
  'table': '12',
  'status': 'received',
  'items': [
    {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
  ],
  'totalCents': 6580,
  'createdAt': '2026-10-16T18:00:00Z',
};

const _newer = {
  'id': 'o2',
  'table': '8',
  'status': 'preparing',
  'items': [
    {'productId': 'p2', 'quantity': 1},
  ],
  'totalCents': 3290,
  'createdAt': '2026-10-16T18:05:00.000Z',
};

void main() {
  final baseUrl = Uri.parse('http://localhost:3333');

  HttpOrderRepository repositoryReturning(http.Response response) {
    return HttpOrderRepository(
      ApiClient(baseUrl: baseUrl, httpClient: MockClient((_) async => response)),
    );
  }

  test('lista pedidos válidos em GET /orders', () async {
    late http.Request requested;
    final repository = HttpOrderRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requested = request;
          return http.Response(
            jsonEncode([_newer, _older]),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await repository.list();
    final orders = result.orders!;

    expect(requested.method, 'GET');
    expect(requested.url.toString(), 'http://localhost:3333/orders');
    expect(requested.url.query, isEmpty);
    expect(result.message, isNull);
    expect(orders.map((order) => order.id), ['o2', 'o1']);
    expect(orders.first.table, '8');
    expect(orders.first.status.name, 'preparing');
    expect(orders.first.items.single.note, isNull);
    expect(orders.first.totalCents, 3290);
    expect(orders.first.createdAt, DateTime.utc(2026, 10, 16, 18, 5));
    expect(orders.last.table, '12');
    expect(orders.last.status.name, 'received');
    expect(orders.last.items.single.note, 'sem cebola');
    expect(orders.last.totalCents, 6580);
    expect(orders.last.createdAt, DateTime.utc(2026, 10, 16, 18));
    expect(orders.last.createdAt.isUtc, isTrue);
  });

  test('aceita lista vazia como fila sem pedidos', () async {
    final repository = repositoryReturning(
      http.Response('[]', 200, headers: const {'content-type': 'application/json; charset=utf-8'}),
    );

    final result = await repository.list();

    expect(result.orders, isEmpty);
    expect(result.message, isNull);
  });

  test('traduz JSON incompatível com a lista do contrato', () async {
    final wrapped = repositoryReturning(
      http.Response(
        jsonEncode({
          'orders': [_older],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final brokenItem = repositoryReturning(
      http.Response(
        jsonEncode([
          {'id': 'o1', 'table': '12'},
        ]),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final invalidInstant = repositoryReturning(
      http.Response(
        jsonEncode([
          {..._older, 'createdAt': '2026-10-16T15:00:00-03:00'},
        ]),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final emptyBody = repositoryReturning(
      http.Response('', 200, headers: const {'content-type': 'application/json; charset=utf-8'}),
    );

    final objectBody = await wrapped.list();
    final missingFields = await brokenItem.list();
    final offset = await invalidInstant.list();
    final blank = await emptyBody.list();

    expect(objectBody.orders, isNull);
    expect(objectBody.message, HttpOrderRepository.unexpectedResponseMessage);
    expect(missingFields.orders, isNull);
    expect(missingFields.message, HttpOrderRepository.unexpectedResponseMessage);
    expect(offset.orders, isNull);
    expect(offset.message, HttpOrderRepository.unexpectedResponseMessage);
    expect(blank.orders, isNull);
    expect(blank.message, HttpOrderRepository.unexpectedResponseMessage);
  });

  test('traduz resposta HTTP inválida na mensagem da API', () async {
    final described = repositoryReturning(
      http.Response(
        jsonEncode({
          'error': {'code': 'UNAVAILABLE', 'message': 'API em manutenção'},
        }),
        503,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final bare = repositoryReturning(
      http.Response('{}', 500, headers: const {'content-type': 'application/json; charset=utf-8'}),
    );

    final maintenance = await described.list();
    final failure = await bare.list();

    expect(maintenance.orders, isNull);
    expect(maintenance.message, 'API em manutenção');
    expect(maintenance.failure, DataFailure.unavailable);
    expect(failure.orders, isNull);
    expect(failure.message, ApiClient.httpFailureMessage);
    expect(failure.message, isNot(contains('Erro HTTP')));
    expect(failure.detail, 'HTTP 500');
    expect(failure.failure, DataFailure.unavailable);
  });

  test('diferencia validação, ausência e conflito', () async {
    Future<OrderList> failed(int status, String message) {
      return repositoryReturning(
        http.Response(
          jsonEncode({
            'error': {'code': 'X', 'message': message},
          }),
          status,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ).list();
    }

    final validation = await failed(400, 'Mesa inválida');
    final missing = await failed(404, 'Pedido não encontrado');
    final conflict = await failed(409, 'Transição inválida');

    expect(validation.message, 'Mesa inválida');
    expect(validation.failure, DataFailure.validation);
    expect(validation.orders, isNull);
    expect(missing.failure, DataFailure.notFound);
    expect(conflict.failure, DataFailure.conflict);
  });

  test('traduz indisponibilidade de rede', () async {
    final offline = HttpOrderRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async => throw const SocketException('Network is unreachable')),
      ),
    );
    final refused = HttpOrderRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async => throw http.ClientException('Connection refused')),
      ),
    );

    final socket = await offline.list();
    final client = await refused.list();

    expect(socket.orders, isNull);
    expect(socket.message, 'Não foi possível conectar à API');
    expect(socket.detail, 'Network is unreachable');
    expect(client.orders, isNull);
    expect(client.message, 'Não foi possível conectar à API');
    expect(client.message, isNot(contains('Connection refused')));
    expect(client.failure, DataFailure.unavailable);
    expect(client.detail, 'Connection refused');
  });
}
