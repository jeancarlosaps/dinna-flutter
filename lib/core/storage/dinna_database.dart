import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Banco local compartilhado por carrinho e pedido confirmado.
///
/// A versão 2 mantém `cart_items` e adiciona a fotografia `last_orders`.
/// Pedidos de versões anteriores do app permanecem no banco; a migração só
/// cria a nova tabela.
class DinnaDatabase {
  DinnaDatabase({DatabaseFactory? factory}) : _factory = factory ?? databaseFactory;

  static const databaseName = 'dinna.db';
  static const lastOrdersTable = 'last_orders';
  static const _cartItemsTable = 'cart_items';
  static const _schemaVersion = 2;

  final DatabaseFactory _factory;
  Future<Database>? _opening;

  Future<Database> get database async {
    final current = _opening;
    if (current != null) return current;

    final opening = _open();
    _opening = opening;
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final directory = await _factory.getDatabasesPath();
    return _factory.openDatabase(
      path.join(directory, databaseName),
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: (database, version) async {
          await _createCartItems(database);
          await _createLastOrders(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createLastOrders(database);
        },
      ),
    );
  }

  Future<void> _createCartItems(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE $_cartItemsTable (
        position INTEGER PRIMARY KEY AUTOINCREMENT,
        line_id TEXT NOT NULL UNIQUE,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity >= 1),
        note TEXT
      )
    ''');
  }

  Future<void> _createLastOrders(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE $lastOrdersTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        order_json TEXT NOT NULL
      )
    ''');
  }
}
