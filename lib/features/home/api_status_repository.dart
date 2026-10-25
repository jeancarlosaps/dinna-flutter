/// Disponibilidade da API já traduzida para o ViewModel.
///
/// Não carrega status HTTP nem exceção de transporte.
class ApiAvailability {
  const ApiAvailability.online() : this._(isOnline: true);

  const ApiAvailability.offline(String message) : this._(isOnline: false, message: message);

  const ApiAvailability._({required this.isOnline, this.message});

  final bool isOnline;

  /// Preenchida só quando a verificação falha.
  final String? message;
}

/// Fonte de dados do fluxo de referência.
///
/// A implementação concreta traduz payload e falhas de transporte
/// para [ApiAvailability]. O ViewModel depende deste contrato.
abstract interface class ApiStatusRepository {
  Future<ApiAvailability> checkHealth();
}
