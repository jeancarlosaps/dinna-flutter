import '../../core/domain/data_failure.dart';

/// Disponibilidade da API já traduzida para o ViewModel.
///
/// Não carrega status HTTP nem exceção de transporte. [failure] classifica
/// a falha; [message] continua sendo o texto da tela.
class ApiAvailability {
  const ApiAvailability.online() : this._(isOnline: true);

  const ApiAvailability.offline(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
  }) : this._(isOnline: false, message: message, failure: failure, detail: detail);

  const ApiAvailability._({required this.isOnline, this.message, this.failure, this.detail});

  final bool isOnline;

  /// Preenchida só quando a verificação falha.
  final String? message;

  /// Nula quando a API está online.
  final DataFailure? failure;

  /// Causa técnica. A tela usa [message].
  final String? detail;
}

/// Fonte de dados do fluxo de referência.
///
/// A implementação concreta traduz payload e falhas de transporte
/// para [ApiAvailability]. O ViewModel depende deste contrato.
abstract interface class ApiStatusRepository {
  Future<ApiAvailability> checkHealth();
}
