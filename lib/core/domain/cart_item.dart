import 'json_values.dart';
import 'order_item.dart';

const _noteMaxLength = 200;

/// Item do carrinho, local ao app.
///
/// Não é recurso da API e não copia nome, preço nem imagem do produto.
/// [toOrderItem] produz o `OrderItem` de `POST /orders`. O total do pedido
/// continua sendo calculado pela API.
final class CartItem {
  CartItem({required this.productId, required this.quantity, required this.note}) {
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

  /// JSON local. As chaves coincidem com as de [OrderItem]; o tipo é outro.
  factory CartItem.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'CartItem');
      return CartItem(
        productId: readRequiredString(map, 'productId'),
        quantity: readRequiredInt(map, 'quantity', min: 1),
        note: readOptionalString(map, 'note', maxLength: _noteMaxLength),
      );
    });
  }

  final String productId;

  /// Inteiro ≥ 1.
  final int quantity;

  /// Observação do cliente. Ausente e `null` significam sem observação.
  final String? note;

  /// Item do contrato, pronto para entrar em `POST /orders`.
  OrderItem toOrderItem() => OrderItem(productId: productId, quantity: quantity, note: note);

  /// Omite `note` quando ela é nula.
  Map<String, Object?> toJson() => {
    'productId': productId,
    'quantity': quantity,
    if (note != null) 'note': note,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CartItem &&
        other.productId == productId &&
        other.quantity == quantity &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(productId, quantity, note);

  @override
  String toString() => 'CartItem(productId: $productId, quantity: $quantity)';
}
