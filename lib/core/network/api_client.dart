import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Ponto único de acesso HTTP à dinna-api. Repositories dependem dele;
/// Views e ViewModels nunca usam `http` diretamente.
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
    } on SocketException {
      throw const ApiException('Não foi possível conectar à API');
    } on http.ClientException catch (error) {
      throw ApiException(error.message);
    }

    final body = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    throw ApiException(
      _errorMessage(body) ?? 'Erro HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  /// Lê o formato de erro da API: `{ "error": { "code", "message" } }`.
  String? _errorMessage(Object? body) {
    if (body case {'error': {'message': final String message}}) return message;
    return null;
  }
}
