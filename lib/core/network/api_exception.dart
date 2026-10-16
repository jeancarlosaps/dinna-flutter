/// Falha ao falar com a API. [statusCode] é nulo quando não houve resposta
/// (sem rede, timeout, servidor fora do ar).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
