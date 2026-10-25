import 'json_values.dart';
import 'order_item.dart';
import 'order_status.dart';

/// Pedido no formato de resposta da API.
///
/// O body de `POST /orders` é só `table` e `items`. `id`, `status`,
/// `totalCents` e `createdAt` nascem na API e são obrigatórios neste model.
final class Order {
  Order({
    required this.id,
    required this.table,
    required this.status,
    required List<OrderItem> items,
    required this.totalCents,
    required this.createdAt,
  }) : items = List<OrderItem>.unmodifiable(items) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'id deve ter ao menos 1 caractere');
    }
    if (table.isEmpty) {
      throw ArgumentError.value(table, 'table', 'table deve ter ao menos 1 caractere');
    }
    if (this.items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'items deve ter ao menos 1 item');
    }
    if (totalCents < 0) {
      throw ArgumentError.value(totalCents, 'totalCents', 'totalCents deve ser >= 0');
    }
    if (!createdAt.isUtc) {
      throw ArgumentError.value(createdAt, 'createdAt', 'createdAt deve estar em UTC');
    }
  }

  factory Order.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'Order');
      return Order(
        id: readRequiredString(map, 'id'),
        table: readRequiredString(map, 'table'),
        status: OrderStatus.parse(readRequiredString(map, 'status')),
        items: readRequiredList(map, 'items', OrderItem.fromJson),
        totalCents: readRequiredInt(map, 'totalCents', min: 0),
        createdAt: readRequiredUtc(map, 'createdAt'),
      );
    });
  }

  final String id;

  /// Identificador da mesa, texto. Exemplo do contrato: `"12"`.
  final String table;

  final OrderStatus status;

  /// Pelo menos um [OrderItem]. A lista é imutável.
  final List<OrderItem> items;

  /// Centavos calculados pela API. Este model não soma preços.
  final int totalCents;

  /// Instante UTC de criação.
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'table': table,
    'status': status.value,
    'items': [for (final item in items) item.toJson()],
    'totalCents': totalCents,
    'createdAt': writeUtcIso8601(createdAt),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Order &&
        other.id == id &&
        other.table == table &&
        other.status == status &&
        _sameItems(other.items, items) &&
        other.totalCents == totalCents &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, table, status, totalCents, createdAt, Object.hashAll(items));

  @override
  String toString() => 'Order(id: $id, status: ${status.value}, totalCents: $totalCents)';
}

bool _sameItems(List<OrderItem> a, List<OrderItem> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
