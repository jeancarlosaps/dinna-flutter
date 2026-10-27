import 'dart:async';

import 'package:dinna/features/restaurant/order_repository.dart';

class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository(this._list);

  final Future<OrderList> Function() _list;
  int calls = 0;

  @override
  Future<OrderList> list() {
    calls++;
    return _list();
  }
}

/// Atraso que nunca agenda um timer. Serve ao `pumpAndSettle`.
Future<void> pendingPollDelay(Duration _) => Completer<void>().future;
