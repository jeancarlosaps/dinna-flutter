/// Motivo de uma operação que não devolveu o dado confirmado.
///
/// O repository traduz o status HTTP. A View continua exibindo só a mensagem.
enum DataFailure {
  /// O pedido de dados não passou na validação.
  validation,

  /// O recurso não existe.
  notFound,

  /// O estado atual não aceita a operação.
  conflict,

  /// Rede, tempo esgotado em consulta, falha do servidor ou resposta fora do contrato.
  unavailable,

  /// O POST pode ter sido aplicado, mas a confirmação não chegou.
  ///
  /// Tempo esgotado ou queda de conexão depois do envio. Não é falha definitiva:
  /// o recurso pode ter sido registrado.
  uncertain,
}
