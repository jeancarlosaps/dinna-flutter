import 'dart:convert';

import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/features/home/http_api_status_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final baseUrl = Uri.parse('http://localhost:3333');

  HttpApiStatusRepository repositoryReturning(http.Response response) {
    return HttpApiStatusRepository(
      ApiClient(baseUrl: baseUrl, httpClient: MockClient((_) async => response)),
    );
  }

  test('traduz status ok em API online', () async {
    final repository = repositoryReturning(http.Response('{"status":"ok"}', 200));

    final availability = await repository.checkHealth();

    expect(availability.isOnline, isTrue);
    expect(availability.message, isNull);
  });

  test('traduz payload inesperado em falha sem expor HTTP', () async {
    final repository = repositoryReturning(http.Response('{"status":"down"}', 200));

    final availability = await repository.checkHealth();

    expect(availability.isOnline, isFalse);
    expect(availability.message, 'Resposta inesperada da API');
  });

  test('traduz erro de rede em falha com a mensagem do Service', () async {
    final repository = HttpApiStatusRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async => throw http.ClientException('Connection refused')),
      ),
    );

    final availability = await repository.checkHealth();

    expect(availability.isOnline, isFalse);
    expect(availability.message, 'Connection refused');
  });

  test('traduz resposta HTTP inválida na mensagem da API', () async {
    final repository = repositoryReturning(
      http.Response(
        jsonEncode({
          'error': {'code': 'UNAVAILABLE', 'message': 'API em manutenção'},
        }),
        503,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final availability = await repository.checkHealth();

    expect(availability.isOnline, isFalse);
    expect(availability.message, 'API em manutenção');
  });
}
