import 'dart:convert';

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
            .having((e) => e.message, 'message', 'Produto não encontrado'),
      ),
    );
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
            .having((error) => error.detail, 'detail', 'Connection refused'),
      ),
    );
  });
}
