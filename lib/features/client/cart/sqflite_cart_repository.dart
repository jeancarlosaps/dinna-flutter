import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../core/domain/cart_item.dart';
import 'cart_repository.dart';

/// Repositório SQLite para o carrinho local do cliente.
class SqfliteCartRepository implements CartRepository {
  SqfliteCartRepository({DatabaseFactory? factory, String Function()? lineIdGenerator})
    : _factory = factory ?? databaseFactory,
      _lineIdGenerator = lineIdGenerator ?? _newLineId;

  static const _databaseName = 'dinna.db';
  static const _table = 'cart_items';
  static const _reconciliations = 'cart_reconciliations';
  static const _version = 2;

  final DatabaseFactory _factory;
  final String Function() _lineIdGenerator;
  Future<Database>? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final opening = _openDatabase();
    _database = opening;
    try {
      return await opening;
    } catch (_) {
      if (identical(_database, opening)) _database = null;
      rethrow;
    }
  }

  Future<Database> _openDatabase() async {
    final directory = await _factory.getDatabasesPath();
    return _factory.openDatabase(
      path.join(directory, _databaseName),
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (database, version) async {
          await _createItems(database);
          await _createReconciliations(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createReconciliations(database);
        },
      ),
    );
  }

  @override
  Future<List<CartItem>> load() async {
    final database = await _db;
    return _readCart(database);
  }

  @override
  Future<CartItem> add({required String productId, required int quantity, String? note}) async {
    final item = CartItem(
      lineId: _lineIdGenerator(),
      productId: productId,
      quantity: quantity,
      note: note,
    );
    final database = await _db;
    await database.insert(_table, _toRow(item));
    return item;
  }

  @override
  Future<bool> update(CartItem item) async {
    final lineId = item.lineId;
    if (lineId == null) {
      throw ArgumentError.value(item, 'item', 'item precisa ter lineId para ser atualizado');
    }

    final database = await _db;
    final changed = await database.update(
      _table,
      {'quantity': item.quantity, 'note': item.note},
      where: 'line_id = ?',
      whereArgs: [lineId],
    );
    return changed > 0;
  }

  @override
  Future<bool> remove(String lineId) async {
    if (lineId.isEmpty) throw ArgumentError.value(lineId, 'lineId', 'lineId não pode ser vazio');

    final database = await _db;
    final changed = await database.delete(_table, where: 'line_id = ?', whereArgs: [lineId]);
    return changed > 0;
  }

  @override
  Future<List<CartItem>> removeConfirmed(List<CartItem> confirmedItems) async {
    final confirmed = List<CartItem>.unmodifiable(confirmedItems);
    final database = await _db;

    return database.transaction((transaction) async {
      await _subtract(transaction, confirmed);
      return _readCart(transaction);
    });
  }

  @override
  Future<CartReconciliationResult> reconcileConfirmed({
    required String intentId,
    required List<CartItem> confirmedItems,
  }) async {
    if (intentId.isEmpty) {
      throw ArgumentError.value(intentId, 'intentId', 'intentId não pode ser vazio');
    }
    final confirmed = List<CartItem>.unmodifiable(confirmedItems);
    final database = await _db;

    return database.transaction((transaction) async {
      final marked = await transaction.query(
        _reconciliations,
        columns: ['intent_id'],
        where: 'intent_id = ?',
        whereArgs: [intentId],
        limit: 1,
      );
      if (marked.isNotEmpty) {
        return CartReconciliationResult(
          items: await _readCart(transaction),
          outcome: CartReconciliation.alreadyApplied,
        );
      }
      if (confirmed.any((item) => item.lineId == null)) {
        return CartReconciliationResult(
          items: await _readCart(transaction),
          outcome: CartReconciliation.unresolved,
        );
      }
      await _subtract(transaction, confirmed);
      await transaction.insert(_reconciliations, {'intent_id': intentId});
      return CartReconciliationResult(
        items: await _readCart(transaction),
        outcome: CartReconciliation.applied,
      );
    });
  }

  Future<void> _subtract(DatabaseExecutor transaction, List<CartItem> confirmed) async {
    final processedLineIds = <String>{};

    for (final sent in confirmed) {
      final lineId = sent.lineId;
      if (lineId == null || !processedLineIds.add(lineId)) continue;

      final rows = await transaction.query(
        _table,
        where: 'line_id = ?',
        whereArgs: [lineId],
        limit: 1,
      );
      if (rows.isEmpty) continue;

      final current = _fromRow(rows.single);
      if (current.note != sent.note) continue;

      final remainingQuantity = current.quantity - sent.quantity;
      if (remainingQuantity < 1) {
        await transaction.delete(_table, where: 'line_id = ?', whereArgs: [lineId]);
      } else {
        await transaction.update(
          _table,
          {'quantity': remainingQuantity},
          where: 'line_id = ?',
          whereArgs: [lineId],
        );
      }
    }
  }

  static Future<void> _createItems(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE $_table (
        position INTEGER PRIMARY KEY AUTOINCREMENT,
        line_id TEXT NOT NULL UNIQUE,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity >= 1),
        note TEXT
      )
    ''');
  }

  static Future<void> _createReconciliations(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE IF NOT EXISTS $_reconciliations (
        intent_id TEXT PRIMARY KEY
      )
    ''');
  }

  Future<List<CartItem>> _readCart(DatabaseExecutor executor) async {
    final rows = await executor.query(_table, orderBy: 'position ASC');
    return List<CartItem>.unmodifiable(rows.map(_fromRow));
  }

  Map<String, Object?> _toRow(CartItem item) => {
    'line_id': item.lineId!,
    'product_id': item.productId,
    'quantity': item.quantity,
    'note': item.note,
  };

  CartItem _fromRow(Map<String, Object?> row) => CartItem(
    lineId: row['line_id']! as String,
    productId: row['product_id']! as String,
    quantity: row['quantity']! as int,
    note: row['note'] as String?,
  );

  static String _newLineId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
