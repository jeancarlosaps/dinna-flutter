import 'json_values.dart';

const _noteMaxLength = 200;
const _nameMaxLength = 120;

/// Item de um pedido (`OrderItem` no contrato REST).
///
/// O body de `POST /orders` manda só `productId`, `quantity` e `note` opcional.
/// A resposta de `GET /orders` também traz `name`, `unitPriceCents` e
/// `lineTotalCents` já resolvidos pela API.
final class OrderItem {
  OrderItem({
    required this.productId,
    required this.quantity,
    required this.note,
    this.name,
    this.unitPriceCents,
    this.lineTotalCents,
  }) {
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
    final productName = name;
    if (productName != null &&
        (productName.isEmpty || productName.length > _nameMaxLength)) {
      throw ArgumentError.value(
        productName,
        'name',
        'name deve ter de 1 a $_nameMaxLength caracteres',
      );
    }
    final unit = unitPriceCents;
    if (unit != null && unit < 0) {
      throw ArgumentError.value(unit, 'unitPriceCents', 'unitPriceCents deve ser >= 0');
    }
    final line = lineTotalCents;
    if (line != null && line < 0) {
      throw ArgumentError.value(line, 'lineTotalCents', 'lineTotalCents deve ser >= 0');
    }
  }

  factory OrderItem.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'OrderItem');
      return OrderItem(
        productId: readRequiredString(map, 'productId'),
        quantity: readRequiredInt(map, 'quantity', min: 1),
        note: readOptionalString(map, 'note', maxLength: _noteMaxLength),
        name: readOptionalString(map, 'name', maxLength: _nameMaxLength),
        unitPriceCents: readOptionalInt(map, 'unitPriceCents'),
        lineTotalCents: readOptionalInt(map, 'lineTotalCents'),
      );
    });
  }

  /// Referência ao produto.
  final String productId;

  /// Inteiro ≥ 1.
  final int quantity;

  /// Observação do cliente. Ausente e `null` significam sem observação.
  final String? note;

  /// Nome do produto na resposta da API. Ausente no body de criação.
  final String? name;

  /// Preço unitário em centavos, na resposta da API.
  final int? unitPriceCents;

  /// Total da linha em centavos, na resposta da API.
  final int? lineTotalCents;

  /// Omite campos nulos. O POST só precisa de productId, quantity e note.
  Map<String, Object?> toJson() => {
    'productId': productId,
    'quantity': quantity,
    if (name != null) 'name': name,
    if (unitPriceCents != null) 'unitPriceCents': unitPriceCents,
    if (lineTotalCents != null) 'lineTotalCents': lineTotalCents,
    if (note != null) 'note': note,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderItem &&
        other.productId == productId &&
        other.quantity == quantity &&
        other.note == note &&
        other.name == name &&
        other.unitPriceCents == unitPriceCents &&
        other.lineTotalCents == lineTotalCents;
  }

  @override
  int get hashCode => Object.hash(productId, quantity, note, name, unitPriceCents, lineTotalCents);

  @override
  String toString() => 'OrderItem(productId: $productId, quantity: $quantity, name: $name)';
}
