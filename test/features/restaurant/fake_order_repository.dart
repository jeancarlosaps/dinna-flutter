import 'dart:async';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/features/restaurant/order_repository.dart';

class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository(this._list, {this.onCreate, this.onFind});

  final Future<OrderList> Function() _list;
  final Future<OrderSubmission> Function({required String table, required List<CartItem> items})?
  onCreate;
  final Future<OrderLookup> Function(String id)? onFind;
  int calls = 0;
  int createCalls = 0;
  int findCalls = 0;
  String? lastIdempotencyKey;
  String? lastFoundId;
  Map<String, Object?>? lastBody;

  @override
  Future<OrderList> list() {
    calls++;
    return _list();
  }

  @override
  Future<OrderLookup> findById(String id) {
    findCalls++;
    lastFoundId = id;
    final find = onFind;
    if (find == null) {
      return Future.value(const OrderLookup.unavailable('Consulta do pedido não configurada'));
    }
    return find(id);
  }

  @override
  Future<OrderSubmission> create({
    required String table,
    required List<CartItem> items,
    String? idempotencyKey,
    Map<String, Object?>? body,
  }) {
    createCalls++;
    lastIdempotencyKey = idempotencyKey;
    lastBody = body;
    final create = onCreate;
    if (create == null) {
      throw UnsupportedError('FakeOrderRepository.create não foi configurado');
    }
    return create(table: table, items: items);
  }
}

/// Atraso que nunca agenda um timer. Serve ao `pumpAndSettle`.
Future<void> pendingPollDelay(Duration _) => Completer<void>().future;
