import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/storage/dinna_database.dart';
import 'package:dinna/features/client/cart/cart_repository.dart';
import 'package:dinna/features/client/cart/sqflite_cart_repository.dart';
import 'package:dinna/features/client/order/last_order_session.dart';
import 'package:dinna/features/client/order/last_order_store.dart';
import 'package:dinna/features/client/order/order_submission_view_model.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../restaurant/fake_order_repository.dart';
import '../../restaurant/sample_order.dart';

void main() {
  late Directory directory;
  late DatabaseFactory factory;
  final openedDatabases = <Database>[];

  setUpAll(() {
    sqfliteFfiInit();
    factory = createDatabaseFactoryFfi(noIsolate: true);
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dinna-last-order-');
    await factory.setDatabasesPath(directory.path);
    openedDatabases.clear();
  });

  tearDown(() async {
    for (final database in openedDatabases) {
      if (database.isOpen) await database.close();
    }
    try {
      await factory.deleteDatabase(path.join(directory.path, DinnaDatabase.databaseName));
    } on Object {
      // O diretório temporário remove o arquivo se o factory já o fechou.
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  const expectedTables = [
    DinnaDatabase.cartItemsTable,
    DinnaDatabase.reconciliationsTable,
    DinnaDatabase.lastOrdersTable,
  ];

  Future<DinnaDatabase> openDatabase() async {
    final database = DinnaDatabase(factory: factory);
    openedDatabases.add(await database.database);
    return database;
  }

  Future<void> createLegacy({
    required int version,
    required Future<void> Function(Database database, int version) onCreate,
  }) async {
    final legacy = await factory.openDatabase(
      path.join(directory.path, DinnaDatabase.databaseName),
      options: OpenDatabaseOptions(version: version, onCreate: onCreate),
    );
    await legacy.close();
  }

  Future<void> createCartItems(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE ${DinnaDatabase.cartItemsTable} (
        position INTEGER PRIMARY KEY AUTOINCREMENT,
        line_id TEXT NOT NULL UNIQUE,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity >= 1),
        note TEXT
      )
    ''');
  }

  Future<void> createReconciliations(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE ${DinnaDatabase.reconciliationsTable} (
        intent_id TEXT PRIMARY KEY
      )
    ''');
  }

  Future<void> createLastOrders(DatabaseExecutor database) {
    return database.execute('''
      CREATE TABLE ${DinnaDatabase.lastOrdersTable} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        order_json TEXT NOT NULL
      )
    ''');
  }

  Future<List<String>> tableNames(Database database) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    return rows.map((row) => row['name']! as String).toList();
  }

  test('SQLite vazio não tem último pedido e uma gravação substitui o anterior', () async {
    final store = SqfliteLastOrderStore(database: await openDatabase());
    final previous = sampleOrder(id: 'o1', table: '9');
    final newest = sampleOrder(id: 'o2', table: '10');

    expect(await store.load(), isNull);
    await store.save(previous);
    await store.save(newest);

    expect(await store.load(), newest);
    final rows = await openedDatabases.single.query(DinnaDatabase.lastOrdersTable);
    expect(rows, hasLength(1));
    expect(rows.single['id'], 1);
  });

  test('JSON inválido no SQLite é tratado como dado corrompido', () async {
    final database = await openDatabase();
    final store = SqfliteLastOrderStore(database: database);
    await store.save(sampleOrder(id: 'o1'));
    await openedDatabases.single.update(
      DinnaDatabase.lastOrdersTable,
      {'order_json': '{'},
      where: 'id = ?',
      whereArgs: const [1],
    );

    await expectLater(
      store.load,
      throwsA(
        isA<LastOrderStoreException>().having(
          (error) => error.problem,
          'problem',
          LastOrderStoreProblem.corrupt,
        ),
      ),
    );
  });

  test('envio confirmado persiste e restaura o pedido em uma nova sessão SQLite', () async {
    final firstDatabase = await openDatabase();
    final order = sampleOrder(id: 'submitted-order');
    final session = LastOrderSession(SqfliteLastOrderStore(database: firstDatabase));
    final submission = OrderSubmissionViewModel(
      FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async => OrderSubmission.created(order),
      ),
      lastOrderSession: session,
    );
    addTearDown(submission.dispose);
    addTearDown(session.dispose);

    await submission.submit(
      table: '12',
      items: [CartItem(productId: 'p1', quantity: 1, note: null)],
    );

    expect(submission.status, OrderSubmissionStatus.succeeded);
    expect(session.isPersisted(order), isTrue);
    await openedDatabases.single.close();

    final restartedDatabase = DinnaDatabase(factory: factory);
    openedDatabases.add(await restartedDatabase.database);
    final restartedSession = LastOrderSession(SqfliteLastOrderStore(database: restartedDatabase));
    addTearDown(restartedSession.dispose);
    await restartedSession.restore();

    expect(restartedSession.order, order);
    expect(restartedSession.isPersisted(order), isTrue);
  });

  test('migra banco v1 sem perder linhas e cria conciliação e último pedido', () async {
    await createLegacy(
      version: 1,
      onCreate: (database, _) async {
        await createCartItems(database);
        await database.insert(DinnaDatabase.cartItemsTable, {
          'line_id': 'legacy-line',
          'product_id': 'p1',
          'quantity': 3,
          'note': 'sem pimenta',
        });
      },
    );

    final database = await openDatabase();
    final cart = SqfliteCartRepository(database: database);
    final lastOrder = SqfliteLastOrderStore(database: database);
    final existing = CartItem(
      lineId: 'legacy-line',
      productId: 'p1',
      quantity: 3,
      note: 'sem pimenta',
    );

    expect(await cart.load(), [existing]);
    await lastOrder.save(sampleOrder(id: 'after-migration'));
    expect(await lastOrder.load(), sampleOrder(id: 'after-migration'));
    final handle = openedDatabases.single;
    expect(await handle.getVersion(), DinnaDatabase.schemaVersion);
    expect(await tableNames(handle), containsAll(expectedTables));

    final applied = await cart.reconcileConfirmed(
      intentId: 'intent-v1',
      confirmedItems: [
        CartItem(lineId: 'legacy-line', productId: 'p1', quantity: 1, note: 'sem pimenta'),
      ],
    );
    expect(applied.outcome, CartReconciliation.applied);
    expect(applied.items.single.quantity, 2);
  });

  test('banco v2 da dev ganha último pedido e conserva a conciliação', () async {
    await createLegacy(
      version: 2,
      onCreate: (database, _) async {
        await createCartItems(database);
        await createReconciliations(database);
        await database.insert(DinnaDatabase.cartItemsTable, {
          'line_id': 'line-dev',
          'product_id': 'p1',
          'quantity': 4,
          'note': null,
        });
        await database.insert(DinnaDatabase.reconciliationsTable, {'intent_id': 'intent-antiga'});
      },
    );

    final database = await openDatabase();
    final cart = SqfliteCartRepository(database: database);
    final handle = openedDatabases.single;

    expect(await handle.getVersion(), DinnaDatabase.schemaVersion);
    expect((await cart.load()).single.quantity, 4);
    expect(await handle.query(DinnaDatabase.reconciliationsTable), [
      {'intent_id': 'intent-antiga'},
    ]);
    expect(await handle.query(DinnaDatabase.lastOrdersTable), isEmpty);

    final repeated = await cart.reconcileConfirmed(
      intentId: 'intent-antiga',
      confirmedItems: [CartItem(lineId: 'line-dev', productId: 'p1', quantity: 4, note: null)],
    );
    expect(repeated.outcome, CartReconciliation.alreadyApplied);
    expect(repeated.items.single.quantity, 4);
    await SqfliteLastOrderStore(database: database).save(sampleOrder(id: 'depois-da-v2'));
    expect(await SqfliteLastOrderStore(database: database).load(), sampleOrder(id: 'depois-da-v2'));
  });

  test('banco v2 da SCRUM-72 ganha a conciliação e conserva o último pedido', () async {
    final order = sampleOrder(id: 'pedido-v2');
    await createLegacy(
      version: 2,
      onCreate: (database, _) async {
        await createCartItems(database);
        await createLastOrders(database);
        await database.insert(DinnaDatabase.cartItemsTable, {
          'line_id': 'line-72',
          'product_id': 'p9',
          'quantity': 2,
          'note': 'gelo',
        });
        await database.insert(DinnaDatabase.lastOrdersTable, {
          'id': 1,
          'order_json': jsonEncode(order.toJson()),
        });
      },
    );

    final database = await openDatabase();
    final cart = SqfliteCartRepository(database: database);
    expect(await SqfliteLastOrderStore(database: database).load(), order);
    expect((await cart.load()).single.lineId, 'line-72');
    final applied = await cart.reconcileConfirmed(
      intentId: 'intent-72',
      confirmedItems: [CartItem(lineId: 'line-72', productId: 'p9', quantity: 1, note: 'gelo')],
    );
    expect(applied.outcome, CartReconciliation.applied);
    expect(applied.items.single.quantity, 1);
    expect(await SqfliteLastOrderStore(database: database).load(), order);
  });

  test('tabela de último pedido já criada na v2 não impede a migração', () async {
    await createLegacy(
      version: 2,
      onCreate: (database, _) async {
        await createCartItems(database);
        await createReconciliations(database);
        await createLastOrders(database);
        await database.insert(DinnaDatabase.cartItemsTable, {
          'line_id': 'line-parcial',
          'product_id': 'p1',
          'quantity': 5,
          'note': null,
        });
        await database.insert(DinnaDatabase.reconciliationsTable, {'intent_id': 'intent-parcial'});
      },
    );

    final database = await openDatabase();
    final handle = openedDatabases.single;
    expect(await handle.getVersion(), DinnaDatabase.schemaVersion);
    expect((await SqfliteCartRepository(database: database).load()).single.quantity, 5);
    expect(await handle.query(DinnaDatabase.reconciliationsTable), [
      {'intent_id': 'intent-parcial'},
    ]);
    expect(await handle.query(DinnaDatabase.lastOrdersTable), isEmpty);
  });

  test('falha de migração conserva o banco e a abertura seguinte conclui', () async {
    await createLegacy(
      version: 1,
      onCreate: (database, _) async {
        await createCartItems(database);
        await database.insert(DinnaDatabase.cartItemsTable, {
          'line_id': 'line-falha',
          'product_id': 'p1',
          'quantity': 6,
          'note': null,
        });
      },
    );

    await expectLater(
      factory.openDatabase(
        path.join(directory.path, DinnaDatabase.databaseName),
        options: OpenDatabaseOptions(
          version: DinnaDatabase.schemaVersion,
          onUpgrade: (database, oldVersion, newVersion) async {
            throw StateError('migração interrompida');
          },
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final probe = await factory.openDatabase(
      path.join(directory.path, DinnaDatabase.databaseName),
      options: OpenDatabaseOptions(version: 1),
    );
    openedDatabases.add(probe);
    expect(await probe.getVersion(), 1);
    expect((await probe.query(DinnaDatabase.cartItemsTable)).single['quantity'], 6);
    await probe.close();

    final database = await openDatabase();
    final handle = openedDatabases.last;
    expect(await handle.getVersion(), DinnaDatabase.schemaVersion);
    expect((await SqfliteCartRepository(database: database).load()).single.quantity, 6);
    expect(await tableNames(handle), containsAll(expectedTables));
  });

  test('falha inesperada de armazenamento não invalida o sucesso confirmado pela API', () async {
    final store = _UnexpectedSaveFailureStore();
    final session = LastOrderSession(store);
    final order = sampleOrder(id: 'o3');
    final submission = OrderSubmissionViewModel(
      FakeOrderRepository(
        () async => OrderList.ready(const []),
        onCreate: ({required table, required items}) async => OrderSubmission.created(order),
      ),
      lastOrderSession: session,
    );
    addTearDown(submission.dispose);
    addTearDown(session.dispose);

    await submission.submit(
      table: '12',
      items: [CartItem(productId: 'p1', quantity: 1, note: null)],
    );

    expect(submission.status, OrderSubmissionStatus.succeeded);
    expect(submission.order, order);
    expect(session.order, order);
    expect(session.isPersisted(order), isFalse);
    expect(session.errorMessage, LastOrderSession.saveFailureMessage);
    expect(session.isSaving, isFalse);

    await session.retry();

    expect(session.isPersisted(order), isTrue);
    expect(await store.load(), order);
  });

  test('uma leitura de retry não substitui pedido novo submetido enquanto ela aguardava', () async {
    final oldOrder = sampleOrder(id: 'old');
    final newOrder = sampleOrder(id: 'new');
    final store = _DelayedReadStore(oldOrder);
    final session = LastOrderSession(store);
    addTearDown(session.dispose);
    await session.restore();
    store.delayNextRead();
    final delayedRead = store.readGate!;

    final retry = session.retry();
    await store.readStarted.future;
    final newOrderPublished = Completer<void>();
    void listenForNewOrder() {
      if (session.order == newOrder && !newOrderPublished.isCompleted) {
        newOrderPublished.complete();
      }
    }

    session.addListener(listenForNewOrder);
    final record = session.record(newOrder);
    await newOrderPublished.future;
    delayedRead.complete(oldOrder);
    await Future.wait([retry, record]);
    session.removeListener(listenForNewOrder);

    expect(session.order, newOrder);
    expect(session.isPersisted(newOrder), isTrue);
    expect(await store.load(), newOrder);
  });

  test('falha de gravação tipada fica pendente e retry persiste a fotografia', () async {
    final store = MemoryLastOrderStore()..failNextSave();
    final session = LastOrderSession(store);
    final order = sampleOrder(id: 'o4');
    addTearDown(session.dispose);

    await session.record(order);

    expect(session.order, order);
    expect(session.isPersisted(order), isFalse);
    expect(session.errorMessage, LastOrderSession.saveFailureMessage);
    expect(session.isSaving, isFalse);

    await session.retry();

    expect(session.isPersisted(order), isTrue);
    expect(session.errorMessage, isNull);
    expect(await store.load(), order);
  });

  test('falha de leitura pode ser recuperada pelo retry', () async {
    final store = MemoryLastOrderStore()..failNextLoad();
    final session = LastOrderSession(store);
    addTearDown(session.dispose);

    await session.restore();

    expect(session.isRestored, isTrue);
    expect(session.isLoading, isFalse);
    expect(session.order, isNull);
    expect(session.errorMessage, LastOrderSession.readFailureMessage);

    await session.retry();

    expect(session.isLoading, isFalse);
    expect(session.errorMessage, isNull);
    expect(session.order, isNull);
  });

  test('persiste o número e completa um pedido antigo sem outra compra', () async {
    final database = await openDatabase();
    final handle = openedDatabases.last;
    final cart = SqfliteCartRepository(database: database);
    await cart.add(productId: 'p1', quantity: 2, note: null);
    final legacy = sampleOrder(id: 'o_antigo', table: '4');
    await handle.insert(DinnaDatabase.lastOrdersTable, {
      'id': 1,
      'order_json': jsonEncode(legacy.toJson()),
    });
    expect(await handle.getVersion(), DinnaDatabase.schemaVersion);
    expect(legacy.toJson().containsKey('orderNumber'), isFalse);

    var lookups = 0;
    final session = LastOrderSession(
      SqfliteLastOrderStore(database: database),
      orderNumberLookup: (id) async {
        lookups++;
        expect(id, legacy.id);
        return 5;
      },
    );
    addTearDown(session.dispose);
    await session.restore();

    expect(lookups, 1);
    expect(session.order, legacy.withOrderNumber(5));
    expect(session.errorMessage, isNull);
    expect(session.isPersisted(legacy), isTrue);
    expect(session.isPersisted(legacy.withOrderNumber(4)), isFalse);
    expect(await SqfliteLastOrderStore(database: database).load(), legacy.withOrderNumber(5));
    expect((await cart.load()).single.productId, 'p1');
    expect((await cart.load()).single.quantity, 2);
    expect(await handle.getVersion(), DinnaDatabase.schemaVersion);

    final raw = (await handle.query(DinnaDatabase.lastOrdersTable)).single['order_json'];
    final again = LastOrderSession(
      SqfliteLastOrderStore(database: database),
      orderNumberLookup: (_) async {
        lookups++;
        return 9;
      },
    );
    addTearDown(again.dispose);
    await again.restore();

    expect(lookups, 1);
    expect(again.order!.orderNumber, 5);
    expect((await handle.query(DinnaDatabase.lastOrdersTable)).single['order_json'], raw);

    await again.record(legacy);
    expect(again.order, legacy.withOrderNumber(5));
    expect((await SqfliteLastOrderStore(database: database).load())!.orderNumber, 5);
  });

  test('falha ao recuperar o número preserva a fotografia antiga', () async {
    final database = await openDatabase();
    final handle = openedDatabases.last;
    final legacy = sampleOrder(id: 'o_antigo', table: '4');
    final raw = jsonEncode(legacy.toJson());
    await handle.insert(DinnaDatabase.lastOrdersTable, {'id': 1, 'order_json': raw});
    final session = LastOrderSession(
      SqfliteLastOrderStore(database: database),
      orderNumberLookup: (_) async => throw StateError('sem rede'),
    );
    addTearDown(session.dispose);

    await session.restore();

    expect(session.order, legacy);
    expect(session.errorMessage, isNull);
    expect((await handle.query(DinnaDatabase.lastOrdersTable)).single['order_json'], raw);

    final quiet = LastOrderSession(
      SqfliteLastOrderStore(database: database),
      orderNumberLookup: (_) async => null,
    );
    addTearDown(quiet.dispose);
    await quiet.restore();

    expect(quiet.order, legacy);
    expect((await handle.query(DinnaDatabase.lastOrdersTable)).single['order_json'], raw);
  });
}

final class _UnexpectedSaveFailureStore implements LastOrderStore {
  final MemoryLastOrderStore _delegate = MemoryLastOrderStore();
  var _fail = true;

  @override
  Future<Order?> load() => _delegate.load();

  @override
  Future<void> save(Order order) async {
    if (_fail) {
      _fail = false;
      throw StateError('unexpected storage failure');
    }
    await _delegate.save(order);
  }
}

final class _DelayedReadStore implements LastOrderStore {
  _DelayedReadStore(this.order);

  Order? order;
  Completer<Order?>? readGate;
  Completer<void> readStarted = Completer<void>();

  void delayNextRead() {
    readGate = Completer<Order?>();
    readStarted = Completer<void>();
  }

  @override
  Future<Order?> load() async {
    final gate = readGate;
    if (gate == null) return order;
    readGate = null;
    if (!readStarted.isCompleted) readStarted.complete();
    return gate.future;
  }

  @override
  Future<void> save(Order order) async {
    this.order = order;
  }
}
