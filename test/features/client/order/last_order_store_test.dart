import 'dart:async';
import 'dart:io';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/storage/dinna_database.dart';
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

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dinna-last-order-');
    factory = databaseFactoryFfi;
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

  Future<DinnaDatabase> openDatabase() async {
    final database = DinnaDatabase(factory: factory);
    openedDatabases.add(await database.database);
    return database;
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

  test('migra banco v1 sem perder linhas do carrinho e cria a tabela de pedidos', () async {
    final legacy = await factory.openDatabase(
      path.join(directory.path, DinnaDatabase.databaseName),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE cart_items (
              position INTEGER PRIMARY KEY AUTOINCREMENT,
              line_id TEXT NOT NULL UNIQUE,
              product_id TEXT NOT NULL,
              quantity INTEGER NOT NULL CHECK (quantity >= 1),
              note TEXT
            )
          ''');
          await database.insert('cart_items', {
            'line_id': 'legacy-line',
            'product_id': 'p1',
            'quantity': 3,
            'note': 'sem pimenta',
          });
        },
      ),
    );
    await legacy.close();

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
    expect(await openedDatabases.single.getVersion(), 2);
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
