import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/domain/order.dart';
import '../../../core/storage/dinna_database.dart';

enum LastOrderStoreProblem { corrupt, unreadable, unwritable }

class LastOrderStoreException implements Exception {
  const LastOrderStoreException(this.problem);

  final LastOrderStoreProblem problem;

  @override
  String toString() => 'LastOrderStoreException(${problem.name})';
}

/// Persiste a fotografia do último pedido no banco SQLite local.
///
/// Implementações convertem falhas de armazenamento e dados inválidos em
/// [LastOrderStoreException], sem deixar exceções do backend escaparem.
abstract interface class LastOrderStore {
  Future<Order?> load();

  Future<void> save(Order order);
}

final class MemoryLastOrderStore implements LastOrderStore {
  Order? _order;
  var _failSave = false;
  var _failLoad = false;

  void failNextSave() => _failSave = true;

  void failNextLoad() => _failLoad = true;

  @override
  Future<Order?> load() async {
    if (_failLoad) {
      _failLoad = false;
      throw const LastOrderStoreException(LastOrderStoreProblem.unreadable);
    }
    final order = _order;
    return order == null ? null : Order.fromJson(order.toJson());
  }

  @override
  Future<void> save(Order order) async {
    if (_failSave) {
      _failSave = false;
      throw const LastOrderStoreException(LastOrderStoreProblem.unwritable);
    }
    _order = Order.fromJson(order.toJson());
  }
}

final class SqfliteLastOrderStore implements LastOrderStore {
  SqfliteLastOrderStore({required this.database});

  final DinnaDatabase database;

  @override
  Future<Order?> load() async {
    try {
      final database = await this.database.database;
      final rows = await database.query(
        DinnaDatabase.lastOrdersTable,
        columns: const ['order_json'],
        where: 'id = ?',
        whereArgs: const [1],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final raw = rows.single['order_json'];
      if (raw is! String) {
        throw const LastOrderStoreException(LastOrderStoreProblem.corrupt);
      }
      return _decode(raw);
    } on LastOrderStoreException {
      rethrow;
    } on Object {
      throw const LastOrderStoreException(LastOrderStoreProblem.unreadable);
    }
  }

  @override
  Future<void> save(Order order) async {
    try {
      final encoded = jsonEncode(order.toJson());
      final database = await this.database.database;
      await database.insert(DinnaDatabase.lastOrdersTable, {
        'id': 1,
        'order_json': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final rows = await database.query(
        DinnaDatabase.lastOrdersTable,
        columns: const ['order_json'],
        where: 'id = ?',
        whereArgs: const [1],
        limit: 1,
      );
      if (rows.length != 1 || rows.single['order_json'] != encoded) {
        throw const LastOrderStoreException(LastOrderStoreProblem.unwritable);
      }
    } on LastOrderStoreException {
      rethrow;
    } on Object {
      throw const LastOrderStoreException(LastOrderStoreProblem.unwritable);
    }
  }

  Order _decode(String raw) {
    try {
      return Order.fromJson(jsonDecode(raw));
    } on Object {
      throw const LastOrderStoreException(LastOrderStoreProblem.corrupt);
    }
  }
}
