import 'dart:io';
import 'dart:typed_data';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/features/client/cart/sqflite_cart_repository.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late DatabaseFactory factory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dinna-cart-');
    factory = databaseFactoryFfi;
    await factory.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    try {
      await factory.deleteDatabase(path.join(directory.path, 'dinna.db'));
    } on Object {
      // O arquivo pode já ter saído com o diretório.
    }
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  SqfliteCartRepository open({String Function()? lineIdGenerator}) {
    var index = 0;
    return SqfliteCartRepository(
      factory: factory,
      lineIdGenerator: lineIdGenerator ?? () => 'line-${++index}',
    );
  }

  test('cria o esquema e lê as inclusões em ordem, com lineId único', () async {
    final repository = open();
    final first = await repository.add(productId: 'p1', quantity: 1, note: null);
    final second = await repository.add(productId: 'p1', quantity: 2, note: 'sem cebola');
    final third = await repository.add(productId: 'p9', quantity: 1, note: null);

    expect([first.lineId, second.lineId, third.lineId], ['line-1', 'line-2', 'line-3']);
    expect(await repository.load(), [first, second, third]);

    final database = await factory.openDatabase(path.join(directory.path, 'dinna.db'));
    final columns = await database.rawQuery('PRAGMA table_info(cart_items)');
    final master = await database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'cart_items'",
    );
    await database.close();

    expect(columns.map((column) => column['name']), [
      'position',
      'line_id',
      'product_id',
      'quantity',
      'note',
    ]);
    final sql = master.single['sql']! as String;
    expect(sql, contains('line_id TEXT NOT NULL UNIQUE'));
    expect(sql, contains('CHECK (quantity >= 1)'));
  });

  test('preserva observação nula e observação vazia', () async {
    final repository = open();
    final absent = await repository.add(productId: 'p1', quantity: 1, note: null);
    final empty = await repository.add(productId: 'p1', quantity: 1, note: '');

    expect(await repository.load(), [absent, empty]);
    expect(absent.note, isNull);
    expect(empty.note, isEmpty);
  });

  test('atualiza e remove somente a linha do lineId', () async {
    final repository = open();
    final first = await repository.add(productId: 'p1', quantity: 1, note: null);
    final second = await repository.add(productId: 'p9', quantity: 2, note: 'gelo');

    final changed = CartItem(
      lineId: first.lineId,
      productId: first.productId,
      quantity: 4,
      note: 'sem gelo',
    );
    expect(await repository.update(changed), isTrue);
    expect(
      await repository.update(
        CartItem(lineId: 'ausente', productId: 'p1', quantity: 1, note: null),
      ),
      isFalse,
    );
    expect(await repository.load(), [changed, second]);

    expect(await repository.remove(first.lineId!), isTrue);
    expect(await repository.remove('ausente'), isFalse);
    expect(() => repository.remove(''), throwsArgumentError);
    expect(await repository.load(), [second]);
  });

  test('reabre o banco com as mesmas linhas', () async {
    final stored = await open().add(productId: 'p1', quantity: 3, note: 'limão');

    final reopened = await open(lineIdGenerator: () => 'nao-usado').load();

    expect(reopened, [stored]);
  });

  test('removeConfirmed tira a linha intacta e ignora item sem lineId', () async {
    final repository = open();
    final confirmed = await repository.add(productId: 'p1', quantity: 2, note: 'sem cebola');
    final twin = await repository.add(productId: 'p1', quantity: 2, note: 'sem cebola');

    final left = await repository.removeConfirmed([
      confirmed,
      CartItem(productId: 'p1', quantity: 2, note: 'sem cebola'),
    ]);

    expect(left, [twin]);
    expect(OrderRequest.body(table: '12', items: [confirmed, twin]), {
      'table': '12',
      'items': [
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
      ],
    });
  });

  test('removeConfirmed conserva quantidade extra e linha criada durante o envio', () async {
    final repository = open();
    final sent = await repository.add(productId: 'p1', quantity: 2, note: null);
    await repository.update(
      CartItem(lineId: sent.lineId, productId: sent.productId, quantity: 5, note: null),
    );
    final createdDuringPost = await repository.add(productId: 'p9', quantity: 1, note: 'nova');

    final left = await repository.removeConfirmed([sent]);

    expect(left, [
      CartItem(lineId: sent.lineId, productId: 'p1', quantity: 3, note: null),
      createdDuringPost,
    ]);
  });

  test('removeConfirmed conserva a linha quando a observação mudou', () async {
    final repository = open();
    final sent = await repository.add(productId: 'p1', quantity: 2, note: 'sem cebola');
    final edited = CartItem(
      lineId: sent.lineId,
      productId: sent.productId,
      quantity: 4,
      note: 'com limão',
    );
    expect(await repository.update(edited), isTrue);

    expect(await repository.removeConfirmed([sent]), [edited]);
  });

  test('removeConfirmed desfaz a transação quando o SQLite falha', () async {
    final repository = open();
    final first = await repository.add(productId: 'p1', quantity: 1, note: null);
    final second = await repository.add(productId: 'p9', quantity: 1, note: null);
    final database = await factory.openDatabase(path.join(directory.path, 'dinna.db'));
    await database.execute('''
      CREATE TRIGGER cart_items_fail_delete
      BEFORE DELETE ON cart_items
      BEGIN
        SELECT RAISE(ROLLBACK, 'falha forçada');
      END
    ''');

    await expectLater(
      repository.removeConfirmed([first, second]),
      throwsA(isA<DatabaseException>()),
    );

    await database.execute('DROP TRIGGER cart_items_fail_delete');
    expect(await repository.load(), [first, second]);
  });

  test('falha ao abrir o banco não é lida como carrinho vazio', () async {
    final repository = SqfliteCartRepository(
      factory: _OpenFails(factory),
      lineIdGenerator: () => 'line-1',
    );

    await expectLater(repository.load(), throwsStateError);
    await expectLater(repository.add(productId: 'p1', quantity: 1, note: null), throwsStateError);
    expect(await open().load(), isEmpty);
  });

  test('chave repetida não apaga a linha já gravada', () async {
    final repository = open(lineIdGenerator: () => 'line-1');
    final stored = await repository.add(productId: 'p1', quantity: 1, note: null);

    await expectLater(
      repository.add(productId: 'p9', quantity: 1, note: null),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repository.load(), [stored]);
  });
}

class _OpenFails implements DatabaseFactory {
  _OpenFails(this._inner);

  final DatabaseFactory _inner;

  @override
  Future<bool> databaseExists(String path) => _inner.databaseExists(path);

  @override
  Future<void> deleteDatabase(String path) => _inner.deleteDatabase(path);

  @override
  Future<String> getDatabasesPath() => _inner.getDatabasesPath();

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) async {
    throw StateError('sqlite indisponível');
  }

  @override
  Future<Uint8List> readDatabaseBytes(String path) => _inner.readDatabaseBytes(path);

  @override
  Future<void> setDatabasesPath(String path) => _inner.setDatabasesPath(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      _inner.writeDatabaseBytes(path, bytes);
}
