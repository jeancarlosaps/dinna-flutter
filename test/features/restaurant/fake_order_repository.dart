import 'dart:async';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/features/restaurant/order_repository.dart';

class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository(this._list, {this.onCreate});

  final Future<OrderList> Function() _list;
  final Future<OrderSubmission> Function({required String table, required List<CartItem> items})?
  onCreate;
  int calls = 0;
  int createCalls = 0;

  @override
  Future<OrderList> list() {
    calls++;
    return _list();
  }

  @override
  Future<OrderSubmission> create({required String table, required List<CartItem> items}) {
    createCalls++;
    final create = onCreate;
    if (create == null) {
      throw UnsupportedError('FakeOrderRepository.create não foi configurado');
    }
    return create(table: table, items: items);
  }
}

/// Atraso que nunca agenda um timer. Serve ao `pumpAndSettle`.
Future<void> pendingPollDelay(Duration _) => Completer<void>().future;
