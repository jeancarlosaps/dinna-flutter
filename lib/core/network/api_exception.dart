import '../domain/data_failure.dart';

/// Falha ao falar com a API. [statusCode] é nulo quando não houve resposta
/// (sem rede, timeout, servidor fora do ar).
///
/// [message] é o texto para a interface. [detail] guarda a causa técnica,
/// como o texto de uma falha de transporte, e não deve ser exibido.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.detail});

  final String message;
  final int? statusCode;

  /// Causa técnica. Nula quando o texto da interface já é o que importa.
  final String? detail;

  /// 400 validação, 404 ausência, 409 conflito. Rede e os demais status
  /// ficam em [DataFailure.unavailable].
  DataFailure get failure => switch (statusCode) {
    400 => DataFailure.validation,
    404 => DataFailure.notFound,
    409 => DataFailure.conflict,
    _ => DataFailure.unavailable,
  };

  @override
  String toString() {
    final technical = detail == null ? '' : ' [$detail]';
    return 'ApiException($statusCode): $message$technical';
  }
}
