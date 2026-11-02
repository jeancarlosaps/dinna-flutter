import '../domain/data_failure.dart';

/// Falha ao falar com a API. [statusCode] é nulo quando não houve resposta
/// (sem rede, timeout, servidor fora do ar).
///
/// [message] é o texto para a interface. [detail] guarda a causa técnica,
/// como o texto de uma falha de transporte, e não deve ser exibido.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.detail,
    this.outcomeUncertain = false,
  });

  final String message;
  final int? statusCode;

  /// `error.code` da API, quando o corpo trouxe um código utilizável.
  final String? code;

  /// Causa técnica. Nula quando o texto da interface já é o que importa.
  final String? detail;

  /// POST sem resposta confirmada. Consultas deixam isto falso.
  final bool outcomeUncertain;

  /// 400 validação, 404 ausência, 409 conflito. [outcomeUncertain] vence o
  /// status: sem confirmação do POST o resultado é [DataFailure.uncertain].
  /// Rede em consulta e os demais status ficam em [DataFailure.unavailable].
  DataFailure get failure {
    if (outcomeUncertain) return DataFailure.uncertain;
    return switch (statusCode) {
      400 => DataFailure.validation,
      404 => DataFailure.notFound,
      409 => DataFailure.conflict,
      _ => DataFailure.unavailable,
    };
  }

  @override
  String toString() {
    final technical = detail == null ? '' : ' [$detail]';
    return 'ApiException($statusCode): $message$technical';
  }
}
