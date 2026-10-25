import 'json_values.dart';

const _noteMaxLength = 200;

/// Item de um pedido (`OrderItem` no contrato REST).
///
/// O carrinho local é outro tipo e só chega aqui pela conversão explícita
/// antes de `POST /orders`. Não há preço neste objeto; o total do pedido
/// vem em `totalCents`.
final class OrderItem {
  OrderItem({required this.productId, required this.quantity, required this.note}) {
    if (productId.isEmpty) {
      throw ArgumentError.value(productId, 'productId', 'productId deve ter ao menos 1 caractere');
    }
    if (quantity < 1) {
      throw ArgumentError.value(quantity, 'quantity', 'quantity deve ser >= 1');
    }
    final observation = note;
    if (observation != null && observation.length > _noteMaxLength) {
      throw ArgumentError.value(
        observation,
        'note',
        'note deve ter no máximo $_noteMaxLength caracteres',
      );
    }
  }

  factory OrderItem.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'OrderItem');
      return OrderItem(
        productId: readRequiredString(map, 'productId'),
        quantity: readRequiredInt(map, 'quantity', min: 1),
        note: readOptionalString(map, 'note', maxLength: _noteMaxLength),
      );
    });
  }

  /// Referência ao produto. O objeto [Product] não vem aninhado.
  final String productId;

  /// Inteiro ≥ 1.
  final int quantity;

  /// Observação do cliente. Ausente e `null` significam sem observação.
  final String? note;

  /// Omite `note` quando ela é nula, como no exemplo do `POST /orders`.
  Map<String, Object?> toJson() => {
    'productId': productId,
    'quantity': quantity,
    if (note != null) 'note': note,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderItem &&
        other.productId == productId &&
        other.quantity == quantity &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(productId, quantity, note);

  @override
  String toString() => 'OrderItem(productId: $productId, quantity: $quantity)';
}
