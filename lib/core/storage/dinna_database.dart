import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Banco local compartilhado por carrinho, conciliação e último pedido.
///
/// A versão 1 tem `cart_items`. A versão 2, da SCRUM-93, acrescenta
/// `cart_reconciliations` sem alterar as linhas do carrinho. A versão 3, da
/// SCRUM-72, acrescenta `last_orders`.
///
/// A subida aceita um banco antigo e um banco que já passou pela versão 2 da
/// `dev`. Também aceita a versão 2 que a branch da SCRUM-72 criou antes deste
/// merge, em que `last_orders` existia e `cart_reconciliations` ainda não. As
/// tabelas entram com `IF NOT EXISTS`, então uma tentativa interrompida pode
/// ser repetida sem apagar o que já foi gravado.
class DinnaDatabase {
  DinnaDatabase({DatabaseFactory? factory}) : _factory = factory ?? databaseFactory;

  static const databaseName = 'dinna.db';
  static const schemaVersion = 3;
  static const cartItemsTable = 'cart_items';
  static const reconciliationsTable = 'cart_reconciliations';
  static const lastOrdersTable = 'last_orders';

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
        version: schemaVersion,
        onCreate: (database, version) async {
          await _createCartItems(database);
          await _createReconciliations(database);
          await _createLastOrders(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createReconciliations(database);
          if (oldVersion < 3) {
            await _createReconciliations(database);
            await _createLastOrders(database);
          }
        },
      ),
    );
  }

  Future<void> _createCartItems(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $cartItemsTable (
        position INTEGER PRIMARY KEY AUTOINCREMENT,
        line_id TEXT NOT NULL UNIQUE,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity >= 1),
        note TEXT
      )
    ''');
  }

  Future<void> _createReconciliations(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $reconciliationsTable (
        intent_id TEXT PRIMARY KEY
      )
    ''');
  }

  Future<void> _createLastOrders(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $lastOrdersTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        order_json TEXT NOT NULL
      )
    ''');
  }
}
