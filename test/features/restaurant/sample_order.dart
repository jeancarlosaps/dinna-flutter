import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/core/domain/order_status.dart';

Order sampleOrder({
  required String id,
  String table = '12',
  OrderStatus status = OrderStatus.received,
  DateTime? createdAt,
}) {
  return Order(
    id: id,
    table: table,
    status: status,
    items: [OrderItem(productId: 'p1', quantity: 1, note: null)],
    totalCents: 1000,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 16, 18),
  );
}
