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

  /// Texto da interface quando o erro HTTP não traz `error.message` utilizável.
  static const httpFailureMessage = 'Não foi possível concluir a consulta';

  /// POST sem confirmação. A frase é a mesma do contrato de envio do pedido.
  ///
  /// O client não importa a feature. O teste de criação trava este texto no
  /// contrato que a tela vai ler.
  static const uncertainOutcomeMessage =
      'Não foi possível confirmar o envio. O pedido pode ter sido registrado.';

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

    return _interpret(response);
  }

  /// Envia JSON e devolve o corpo em resposta 2xx.
  ///
  /// O contrato de erro é o de [getJson]. Tempo esgotado, ou queda de conexão
  /// depois que a requisição já foi enviada, marca [ApiException.outcomeUncertain]:
  /// o servidor pode ter aplicado o POST. Falha ao conectar, antes de haver
  /// resposta, não marca esse sinal. Não há nova tentativa.
  Future<Object?> postJson(String path, Object? jsonBody) async {
    final request = http.Request('POST', baseUrl.resolve(path))
      ..headers.addAll(const {'Accept': 'application/json', 'Content-Type': 'application/json'})
      ..body = jsonEncode(jsonBody);

    final deadline = DateTime.now().add(timeout);
    Duration remaining() {
      final left = deadline.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }

    final http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request).timeout(remaining());
    } on TimeoutException {
      throw const ApiException(uncertainOutcomeMessage, outcomeUncertain: true);
    } on SocketException catch (error) {
      throw ApiException('Não foi possível conectar à API', detail: error.message);
    } on http.ClientException catch (error) {
      throw ApiException('Não foi possível conectar à API', detail: error.message);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(streamed).timeout(remaining());
    } on TimeoutException {
      throw const ApiException(uncertainOutcomeMessage, outcomeUncertain: true);
    } on SocketException catch (error) {
      throw ApiException(uncertainOutcomeMessage, detail: error.message, outcomeUncertain: true);
    } on http.ClientException catch (error) {
      throw ApiException(uncertainOutcomeMessage, detail: error.message, outcomeUncertain: true);
    }

    return _interpret(response);
  }

  Object? _interpret(http.Response response) {
    final body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    final message = _errorMessage(body);
    throw ApiException(
      message ?? httpFailureMessage,
      statusCode: response.statusCode,
      detail: message == null ? 'HTTP ${response.statusCode}' : null,
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
      final success = response.statusCode >= 200 && response.statusCode < 300;
      throw ApiException(
        success ? 'Resposta inválida da API' : httpFailureMessage,
        statusCode: response.statusCode,
        detail: success ? null : 'HTTP ${response.statusCode}: corpo inválido',
      );
    }
  }

  /// Lê o formato de erro da API: `{ "error": { "code", "message" } }`.
  ///
  /// Mensagem vazia ou só com espaço não conta: o chamador usa o texto amigável.
  String? _errorMessage(Object? body) {
    if (body case {'error': {'message': final String message}} when message.trim().isNotEmpty) {
      return message;
    }
    return null;
  }
}
