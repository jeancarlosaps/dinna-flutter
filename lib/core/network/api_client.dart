import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Service concreto do MVVM: ponto único de acesso HTTP à dinna-api.
///
/// Cuida de URL, timeout, serialização e status code. Com token de execução,
/// acrescenta [accessTokenHeader] sem substituir header que o repositório já
/// definiu. Repositories dependem dele; Views e ViewModels não usam `http`
/// nem este tipo.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this._httpClient,
    String? apiToken,
    this.timeout = const Duration(seconds: 10),
  }) : _apiToken = _usableToken(apiToken);

  /// Header da proteção temporária do ambiente. Não é sessão de usuário.
  static const accessTokenHeader = 'X-Dinna-Api-Token';

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _httpClient;
  final String? _apiToken;

  static String? _usableToken(String? raw) {
    final token = raw?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  bool _hasAccessToken(Map<String, String> headers) {
    final name = accessTokenHeader.toLowerCase();
    for (final key in headers.keys) {
      if (key.toLowerCase() == name) return true;
    }
    return false;
  }

  Map<String, String> _withAccessToken(Map<String, String> headers) {
    final token = _apiToken;
    if (token == null || _hasAccessToken(headers)) return headers;
    return {...headers, accessTokenHeader: token};
  }

  void _applyAccessToken(http.BaseRequest request) {
    final token = _apiToken;
    if (token == null || _hasAccessToken(request.headers)) return;
    request.headers[accessTokenHeader] = token;
  }

  /// Texto da interface quando o erro HTTP não traz `error.message` utilizável.
  static const httpFailureMessage = 'Não foi possível concluir a consulta';

  /// POST sem confirmação. A frase é a mesma do contrato de envio do pedido.
  ///
  /// O client não importa a feature. O teste de criação trava este texto no
  /// contrato que a tela vai ler.
  static const uncertainOutcomeMessage =
      'Não foi possível confirmar o envio. O pedido pode ter sido registrado.';

  Future<Object?> getJson(String path) async {
    return _send(
      () => _httpClient.get(
        baseUrl.resolve(path),
        headers: _withAccessToken(const {'Accept': 'application/json'}),
      ),
    );
  }

  /// `POST` JSON em que a resposta 2xx confirma o recurso. Timeout é falha.
  ///
  /// O envio de pedido continua em [postJson], que trata queda depois do body
  /// como resultado incerto. Cadastro de produto não tem essa chave.
  Future<Object?> createJson(String path, Map<String, Object?> body) {
    return _send(
      () => _httpClient.post(
        baseUrl.resolve(path),
        headers: _withAccessToken(const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        }),
        body: jsonEncode(body),
      ),
    );
  }

  /// `PUT` com corpo JSON. Usado por `PUT /products/:id`.
  Future<Object?> putJson(String path, Map<String, Object?> body) {
    return _send(
      () => _httpClient.put(
        baseUrl.resolve(path),
        headers: _withAccessToken(const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        }),
        body: jsonEncode(body),
      ),
    );
  }

  /// `DELETE` sem corpo. `204` devolve `null`.
  Future<Object?> delete(String path) {
    return _send(
      () => _httpClient.delete(
        baseUrl.resolve(path),
        headers: _withAccessToken(const {'Accept': 'application/json'}),
      ),
    );
  }

  /// `PATCH` com corpo JSON. Usado por `PATCH /orders/:id/status`.
  Future<Object?> patchJson(String path, Map<String, Object?> body) {
    return _send(
      () => _httpClient.patch(
        baseUrl.resolve(path),
        headers: _withAccessToken(const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        }),
        body: jsonEncode(body),
      ),
    );
  }

  Future<Object?> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
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
  /// [http.Client.send] só retorna quando os headers chegam. Uma exceção aí
  /// não prova que o servidor deixou de receber o body e marca
  /// [ApiException.outcomeUncertain]. Se os headers já chegaram, o status
  /// fica na exceção e o corpo ilegível não marca incerteza: 2xx ilegível
  /// permanece incerto, e 4xx/5xx ilegível conserva o status sem `error.code`.
  /// Quem decide se isso libera, bloqueia ou reenvia a chave é o repositório
  /// do pedido. Não há nova tentativa. [getJson] não usa este sinal.
  Future<Object?> postJson(String path, Object? jsonBody, {Map<String, String>? headers}) async {
    final request = http.Request('POST', baseUrl.resolve(path))
      ..headers.addAll(const {'Accept': 'application/json', 'Content-Type': 'application/json'});
    if (headers != null) request.headers.addAll(headers);
    _applyAccessToken(request);
    request.body = jsonEncode(jsonBody);

    final deadline = DateTime.now().add(timeout);
    Duration remaining() {
      final left = deadline.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }

    ApiException uncertain(String? detail) =>
        ApiException(uncertainOutcomeMessage, detail: detail, outcomeUncertain: true);

    final http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request).timeout(remaining());
    } on TimeoutException {
      throw uncertain(null);
    } on SocketException catch (error) {
      throw uncertain(error.message);
    } on HttpException catch (error) {
      throw uncertain(error.message);
    } on http.ClientException catch (error) {
      throw uncertain(error.message);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(streamed).timeout(remaining());
    } on TimeoutException {
      throw _bodyReadFailure(streamed, null);
    } catch (error) {
      throw _bodyReadFailure(streamed, _transportDetail(error));
    }

    final Object? body;
    try {
      body = _interpret(response);
    } on ApiException catch (error) {
      if (_accepted(error.statusCode)) {
        throw ApiException(
          uncertainOutcomeMessage,
          statusCode: error.statusCode,
          detail: error.detail ?? error.message,
          outcomeUncertain: true,
        );
      }
      rethrow;
    } on FormatException {
      // `response.body` decodifica UTF-8 antes de `_decodeBody` e perde o status.
      throw _invalidBody(response.statusCode);
    }
    if (body == null) {
      throw ApiException(
        uncertainOutcomeMessage,
        statusCode: response.statusCode,
        detail: 'corpo vazio',
        outcomeUncertain: true,
      );
    }
    return body;
  }

  bool _accepted(int? statusCode) => statusCode != null && statusCode >= 200 && statusCode < 300;

  String? _transportDetail(Object error) => switch (error) {
    SocketException(:final message) => message,
    HttpException(:final message) => message,
    http.ClientException(:final message) => message,
    _ => error.toString(),
  };

  /// Corpo ilegível com status já conhecido. Erro HTTP permanece confirmado.
  ApiException _invalidBody(int statusCode) {
    if (_accepted(statusCode)) {
      return ApiException(
        uncertainOutcomeMessage,
        statusCode: statusCode,
        detail: 'Resposta inválida da API',
        outcomeUncertain: true,
      );
    }
    return ApiException(
      httpFailureMessage,
      statusCode: statusCode,
      detail: 'HTTP $statusCode: corpo inválido',
      outcomeUncertain: false,
    );
  }

  /// Headers já recebidos. Erro HTTP permanece confirmado; sucesso sem corpo
  /// legível continua incerto.
  ApiException _bodyReadFailure(http.StreamedResponse response, String? detail) {
    final status = response.statusCode;
    if (_accepted(status)) {
      return ApiException(uncertainOutcomeMessage, detail: detail, outcomeUncertain: true);
    }
    return ApiException(
      httpFailureMessage,
      statusCode: status,
      detail: detail ?? 'HTTP $status',
      outcomeUncertain: false,
    );
  }

  Object? _interpret(http.Response response) {
    final body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    final message = _errorMessage(body);
    throw ApiException(
      message ?? httpFailureMessage,
      statusCode: response.statusCode,
      code: _errorCode(body),
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

  /// Código estável da API. Mensagem vazia não impede o código de existir.
  String? _errorCode(Object? body) {
    if (body case {'error': {'code': final String code}} when code.trim().isNotEmpty) {
      return code;
    }
    return null;
  }
}
