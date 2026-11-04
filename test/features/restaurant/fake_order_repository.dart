import 'dart:async';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:dinna/features/restaurant/order_repository.dart';

class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository(
    this._list, {
    this.onCreate,
    Future<OrderUpdate> Function(String id, OrderStatus status)? updateStatus,
  }) : _onUpdateStatus = updateStatus;

  final Future<OrderList> Function() _list;
  final Future<OrderSubmission> Function({required String table, required List<CartItem> items})?
  onCreate;
  final Future<OrderUpdate> Function(String id, OrderStatus status)? _onUpdateStatus;
  int calls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  String? lastIdempotencyKey;
  Map<String, Object?>? lastBody;
  String? lastUpdateId;
  OrderStatus? lastUpdateStatus;

  @override
  Future<OrderList> list() {
    calls++;
    return _list();
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

  @override
  Future<OrderUpdate> updateStatus({required String id, required OrderStatus status}) {
    updateCalls++;
    lastUpdateId = id;
    lastUpdateStatus = status;
    final update = _onUpdateStatus;
    if (update == null) {
      return Future.value(const OrderUpdate.unavailable('Atualização de status não configurada'));
    }
    return update(id, status);
  }
}

/// Atraso que nunca agenda um timer. Serve ao `pumpAndSettle`.
Future<void> pendingPollDelay(Duration _) => Completer<void>().future;
