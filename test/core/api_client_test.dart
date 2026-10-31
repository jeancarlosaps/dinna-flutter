import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final baseUrl = Uri.parse('http://localhost:3333');

  ApiClient clientReturning(http.Response response) {
    return ApiClient(baseUrl: baseUrl, httpClient: MockClient((_) async => response));
  }

  test('monta a URL a partir da baseUrl e decodifica o JSON', () async {
    late Uri requested;
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }),
    );

    final body = await client.getJson('/health');

    expect(requested.toString(), 'http://localhost:3333/health');
    expect(body, {'status': 'ok'});
  });

  test('converte o formato de erro da API em ApiException', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'error': {'code': 'NOT_FOUND', 'message': 'Produto não encontrado'},
        }),
        404,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    await expectLater(
      client.getJson('/products/x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'Produto não encontrado')
            .having((e) => e.detail, 'detail', isNull)
            .having((e) => e.failure, 'failure', DataFailure.notFound)
            .having((e) => e.outcomeUncertain, 'outcomeUncertain', isFalse),
      ),
    );
  });

  test('erro sem mensagem usa texto amigável e guarda o status', () async {
    Future<ApiException> failed(int status, String body) async {
      final client = clientReturning(http.Response(body, status));
      try {
        await client.getJson('/orders');
      } on ApiException catch (error) {
        return error;
      }
      fail('esperava ApiException');
    }

    final empty = {
      for (final status in [400, 404, 409, 500]) status: await failed(status, ''),
    };
    final malformed = {
      for (final status in [400, 404, 409, 500]) status: await failed(status, 'not-json'),
    };
    final blank = await failed(
      500,
      jsonEncode({
        'error': {'message': '  '},
      }),
    );

    expect(empty[400]!.failure, DataFailure.validation);
    expect(empty[404]!.failure, DataFailure.notFound);
    expect(empty[409]!.failure, DataFailure.conflict);
    expect(empty[500]!.failure, DataFailure.unavailable);

    for (final status in [400, 404, 409, 500]) {
      expect(empty[status]!.statusCode, status);
      expect(empty[status]!.message, ApiClient.httpFailureMessage);
      expect(empty[status]!.message, isNot(contains('Erro HTTP')));
      expect(empty[status]!.detail, 'HTTP $status');

      expect(malformed[status]!.statusCode, status);
      expect(malformed[status]!.message, ApiClient.httpFailureMessage);
      expect(malformed[status]!.message, isNot(contains('Erro HTTP')));
      expect(malformed[status]!.detail, 'HTTP $status: corpo inválido');
      expect(malformed[status]!.failure, empty[status]!.failure);
    }

    expect(blank.message, ApiClient.httpFailureMessage);
    expect(blank.statusCode, 500);
    expect(blank.detail, 'HTTP 500');
    expect(blank.failure, DataFailure.unavailable);
  });

  test('rejeita corpo que não é JSON em resposta de sucesso', () async {
    final client = clientReturning(http.Response('not-json', 200));

    await expectLater(
      client.getJson('/health'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 200)
            .having((e) => e.message, 'message', 'Resposta inválida da API'),
      ),
    );
  });

  test('converte falha de rede em ApiException sem statusCode', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient((_) async => throw http.ClientException('Connection refused')),
    );

    await expectLater(
      client.getJson('/health'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', isNull)
            .having((error) => error.message, 'message', 'Não foi possível conectar à API')
            .having((error) => error.detail, 'detail', 'Connection refused')
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isFalse),
      ),
    );
  });

  test('POST envia JSON, devolve o corpo do 201 e não repete a chamada', () async {
    final calls = <http.Request>[];
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient((request) async {
        calls.add(request);
        return http.Response(
          jsonEncode({'id': 'o1', 'status': 'received'}),
          201,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final body = await client.postJson('/orders', {
      'table': '12',
      'items': [
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
      ],
    });

    expect(calls, hasLength(1));
    expect(calls.single.method, 'POST');
    expect(calls.single.url.toString(), 'http://localhost:3333/orders');
    expect(calls.single.headers['content-type'], 'application/json');
    expect(calls.single.headers['accept'], 'application/json');
    expect(jsonDecode(calls.single.body), {
      'table': '12',
      'items': [
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
      ],
    });
    expect(body, {'id': 'o1', 'status': 'received'});
  });

  test('POST com erro HTTP preserva status e não marca incerteza', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'error': {'code': 'VALIDATION_ERROR', 'message': 'Mesa inválida'},
        }),
        400,
        headers: const {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      client.postJson('/orders', const {'table': '12', 'items': []}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.message, 'message', 'Mesa inválida')
            .having((error) => error.failure, 'failure', DataFailure.validation)
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isFalse),
      ),
    );
  });

  test('POST esgotado antes da resposta é incerto e não é repetido', () async {
    var calls = 0;
    final client = ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(milliseconds: 20),
      httpClient: MockClient((request) {
        calls++;
        expect(request.method, 'POST');
        return Completer<http.Response>().future;
      }),
    );

    await expectLater(
      client.postJson('/orders', const {'table': '12'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', isNull)
            .having((error) => error.message, 'message', ApiClient.uncertainOutcomeMessage)
            .having((error) => error.failure, 'failure', DataFailure.uncertain)
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isTrue),
      ),
    );
    expect(calls, 1);
  });

  test('POST com falha de transporte em send não afirma que o pedido ficou no aparelho', () async {
    Future<void> expectUncertain(http.Client httpClient, String detail) {
      final client = ApiClient(baseUrl: baseUrl, httpClient: httpClient);
      return expectLater(
        client.postJson('/orders', const {'table': '12'}),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', isNull)
              .having((error) => error.message, 'message', ApiClient.uncertainOutcomeMessage)
              .having((error) => error.detail, 'detail', detail)
              .having((error) => error.failure, 'failure', DataFailure.uncertain)
              .having((error) => error.outcomeUncertain, 'outcomeUncertain', isTrue),
        ),
      );
    }

    await expectUncertain(
      MockClient((_) async => throw const SocketException('Connection refused')),
      'Connection refused',
    );
    await expectUncertain(
      MockClient((_) async => throw http.ClientException('Connection closed')),
      'Connection closed',
    );
    await expectUncertain(
      MockClient((_) async => throw const HttpException('Connection closed before full header')),
      'Connection closed before full header',
    );
  });

  test('POST 201 ilegível é incerto e o erro HTTP continua confirmado', () async {
    final invalid = clientReturning(http.Response('not-json', 201));
    final empty = clientReturning(http.Response('', 201));
    final rejected = clientReturning(
      http.Response(
        jsonEncode({
          'error': {'code': 'VALIDATION_ERROR', 'message': 'Mesa inválida'},
        }),
        400,
        headers: const {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      invalid.postJson('/orders', const {'table': '12'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 201)
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isTrue)
            .having((error) => error.failure, 'failure', DataFailure.uncertain)
            .having((error) => error.message, 'message', ApiClient.uncertainOutcomeMessage)
            .having((error) => error.detail, 'detail', 'Resposta inválida da API'),
      ),
    );
    await expectLater(
      empty.postJson('/orders', const {'table': '12'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 201)
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isTrue)
            .having((error) => error.detail, 'detail', 'corpo vazio'),
      ),
    );
    await expectLater(
      rejected.postJson('/orders', const {'table': '12'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isFalse)
            .having((error) => error.failure, 'failure', DataFailure.validation)
            .having((error) => error.message, 'message', 'Mesa inválida'),
      ),
    );
  });

  test('POST com queda depois do envio é incerto', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: _BodyErrorClient(const SocketException('Connection reset by peer')),
    );
    final httpFailure = ApiClient(
      baseUrl: baseUrl,
      httpClient: _BodyErrorClient(const HttpException('Connection closed while receiving data')),
    );

    await expectLater(
      client.postJson('/orders', const {'table': '12'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', isNull)
            .having((error) => error.message, 'message', ApiClient.uncertainOutcomeMessage)
            .having((error) => error.detail, 'detail', 'Connection reset by peer')
            .having((error) => error.failure, 'failure', DataFailure.uncertain)
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isTrue),
      ),
    );
    await expectLater(
      httpFailure.postJson('/orders', const {'table': '12'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', isNull)
            .having((error) => error.message, 'message', ApiClient.uncertainOutcomeMessage)
            .having((error) => error.detail, 'detail', 'Connection closed while receiving data')
            .having((error) => error.failure, 'failure', DataFailure.uncertain)
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isTrue),
      ),
    );
  });

  test('POST com headers de erro preserva o status quando o corpo falha', () async {
    Future<void> expectConfirmed(int status, DataFailure failure, Object error, String detail) {
      final client = ApiClient(
        baseUrl: baseUrl,
        httpClient: _BodyErrorClient(error, statusCode: status),
      );
      return expectLater(
        client.postJson('/orders', const {'table': '12'}),
        throwsA(
          isA<ApiException>()
              .having((exception) => exception.statusCode, 'statusCode', status)
              .having((exception) => exception.message, 'message', ApiClient.httpFailureMessage)
              .having((exception) => exception.detail, 'detail', detail)
              .having((exception) => exception.outcomeUncertain, 'outcomeUncertain', isFalse)
              .having((exception) => exception.failure, 'failure', failure),
        ),
      );
    }

    await expectConfirmed(400, DataFailure.validation, const SocketException('reset'), 'reset');
    await expectConfirmed(404, DataFailure.notFound, const HttpException('closed'), 'closed');
    await expectConfirmed(409, DataFailure.conflict, http.ClientException('closed'), 'closed');
    await expectConfirmed(
      500,
      DataFailure.unavailable,
      StateError('truncado'),
      'Bad state: truncado',
    );
  });

  test('POST 500 com tempo esgotado na leitura continua falha confirmada', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(milliseconds: 20),
      httpClient: _HangingBodyClient(statusCode: 500),
    );

    await expectLater(
      client.postJson('/orders', const {'table': '12'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having((error) => error.message, 'message', ApiClient.httpFailureMessage)
            .having((error) => error.detail, 'detail', 'HTTP 500')
            .having((error) => error.failure, 'failure', DataFailure.unavailable)
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isFalse),
      ),
    );
  });

  test('POST com tempo esgotado ao ler a resposta é incerto', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(milliseconds: 20),
      httpClient: _HangingBodyClient(),
    );

    await expectLater(
      client.postJson('/orders', const {'table': '12'}),
      throwsA(
        isA<ApiException>()
            .having((error) => error.outcomeUncertain, 'outcomeUncertain', isTrue)
            .having((error) => error.failure, 'failure', DataFailure.uncertain)
            .having((error) => error.message, 'message', ApiClient.uncertainOutcomeMessage),
      ),
    );
  });
}

/// A requisição sai; a leitura do corpo cai.
class _BodyErrorClient extends http.BaseClient {
  _BodyErrorClient(this._error, {this.statusCode = 201});

  final Object _error;
  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(Stream<List<int>>.error(_error), statusCode);
  }
}

/// A requisição sai; o corpo não chega.
class _HangingBodyClient extends http.BaseClient {
  _HangingBodyClient({this.statusCode = 201});

  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream<List<int>>.fromFuture(Completer<List<int>>().future),
      statusCode,
    );
  }
}
