/// Motivo de uma consulta que não devolveu dado.
///
/// O repository traduz o status HTTP. A View continua exibindo só a mensagem.
enum DataFailure {
  /// O pedido de dados não passou na validação.
  validation,

  /// O recurso não existe.
  notFound,

  /// O estado atual não aceita a operação.
  conflict,

  /// Rede, tempo esgotado, falha do servidor ou resposta fora do contrato.
  unavailable,
}
