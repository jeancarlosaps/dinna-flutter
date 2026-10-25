/// Ciclo de status do pedido no contrato: received → preparing → ready → finished.
///
/// Só é válido avançar um passo. Outro valor JSON é erro, sem status coringa.
enum OrderStatus {
  received('received'),
  preparing('preparing'),
  ready('ready'),
  finished('finished');

  const OrderStatus(this.value);

  /// Chave JSON do contrato, em minúsculas.
  final String value;

  static OrderStatus parse(String raw) {
    for (final status in OrderStatus.values) {
      if (status.value == raw) return status;
    }
    throw FormatException('status desconhecido: $raw');
  }

  /// Transição de um passo documentada no contrato.
  bool canTransitionTo(OrderStatus target) => switch (this) {
    OrderStatus.received => target == OrderStatus.preparing,
    OrderStatus.preparing => target == OrderStatus.ready,
    OrderStatus.ready => target == OrderStatus.finished,
    OrderStatus.finished => false,
  };
}
