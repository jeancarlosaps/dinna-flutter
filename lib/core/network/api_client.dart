import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Service concreto do MVVM: ponto único de acesso HTTP à dinna-api.
///
/// Cuida de URL, timeout, serialização e status code. Repositories dependem
/// dele; Views e ViewModels não usam `http` nem este tipo.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this._httpClient,
    this.timeout = const Duration(seconds: 10),
  });

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _httpClient;

  Future<Object?> getJson(String path) async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(baseUrl.resolve(path), headers: const {'Accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException('Tempo de resposta esgotado');
    } on SocketException catch (error) {
      throw ApiException('Não foi possível conectar à API', detail: error.message);
    } on http.ClientException catch (error) {
      throw ApiException('Não foi possível conectar à API', detail: error.message);
    }

    final body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    throw ApiException(
      _errorMessage(body) ?? 'Erro HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  /// JSON do corpo, ou `null` quando ele vem vazio.
  ///
  /// Corpo que não é JSON vira [ApiException] para o Repository traduzir.
  /// Sem isso, um `FormatException` escaparia e a tela ficaria em carregamento.
  Object? _decodeBody(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(
        response.statusCode >= 200 && response.statusCode < 300
            ? 'Resposta inválida da API'
            : 'Erro HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  /// Lê o formato de erro da API: `{ "error": { "code", "message" } }`.
  String? _errorMessage(Object? body) {
    if (body case {'error': {'message': final String message}}) return message;
    return null;
  }
}
