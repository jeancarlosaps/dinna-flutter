import 'dart:io';

import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/core/storage/dinna_database.dart';
import 'package:dinna/features/client/cart/cart_session.dart';
import 'package:dinna/features/client/cart/sqflite_cart_repository.dart';
import 'package:dinna/features/client/order/last_order_store.dart';
import 'package:dinna/features/client/order/order_confirmation_view.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:dinna/features/client/table/table_view.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../home/fake_api_status_repository.dart';
import '../../menu/fake_product_repository.dart';
import '../../restaurant/fake_order_repository.dart' show FakeOrderRepository;
import '../../restaurant/sample_order.dart';

void main() {
  late Directory directory;
  late DatabaseFactory factory;

  setUpAll(() {
    sqfliteFfiInit();
    factory = createDatabaseFactoryFfi(noIsolate: true);
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dinna-last-order-app-');
    await factory.setDatabasesPath(directory.path);
  });

  tearDown(() async {
    try {
      await factory.deleteDatabase(path.join(directory.path, DinnaDatabase.databaseName));
    } on Object {
      // O diretório temporário remove o arquivo se o factory já o fechou.
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets('reinício restaura o último pedido pelo mesmo SQLite', (tester) async {
    final order = sampleOrder(id: 'restart-order', table: '4');
    final intentFile = File(path.join(directory.path, 'order-intent.json'));
    final firstDatabase = DinnaDatabase(factory: factory);
    var nextLine = 0;
    final firstRepository = SqfliteCartRepository(
      database: firstDatabase,
      lineIdGenerator: () => 'line-${++nextLine}',
    );
    final firstOrders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async {
        expect(table, '12');
        expect(items, hasLength(1));
        expect(items.single.productId, 'p1');
        expect(items.single.quantity, 2);
        return OrderSubmission.created(order);
      },
    );

    await tester.runAsync(() => firstRepository.add(productId: 'p1', quantity: 2, note: null));

    final firstSession = CartSession(firstRepository);
    await tester.runAsync(firstSession.restore);

    await tester.pumpWidget(
      _app(
        database: firstDatabase,
        repository: firstRepository,
        session: firstSession,
        intentFile: intentFile,
        orders: firstOrders,
      ),
    );
    await tester.pump();

    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.cart, arguments: '12');
    await _until(tester, find.text('Enviar pedido'));
    await tester.runAsync(
      () => firstRepository.add(productId: 'p2', quantity: 1, note: 'fora do envio'),
    );
    await tester.ensureVisible(find.text('Enviar pedido'));
    await tester.tap(find.text('Enviar pedido'));
    await _until(tester, find.byType(OrderConfirmationView));

    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('restart-order'), findsOneWidget);
    expect(firstOrders.createCalls, 1);
    await tester.runAsync(() async {
      final database = await firstDatabase.database;
      for (var attempt = 0; attempt < 50; attempt++) {
        final marks = await database.query(DinnaDatabase.reconciliationsTable);
        final orders = await database.query(DinnaDatabase.lastOrdersTable);
        if (marks.isNotEmpty && orders.isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('O pedido confirmado não ficou no SQLite.');
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() async {
      final handle = await firstDatabase.database;
      if (handle.isOpen) await handle.close();
    });

    final secondDatabase = DinnaDatabase(factory: factory);
    final secondRepository = SqfliteCartRepository(
      database: secondDatabase,
      lineIdGenerator: () => 'nao-usado',
    );
    final secondOrders = FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate: ({required table, required items}) async =>
          OrderSubmission.created(sampleOrder(id: 'nao-deve')),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _app(
          database: secondDatabase,
          repository: secondRepository,
          intentFile: intentFile,
          orders: secondOrders,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await _until(tester, find.text('Mesa 4 · restart-order'));
    expect(secondOrders.createCalls, 0);

    await tester.ensureVisible(find.text('Ver último pedido'));
    await tester.tap(find.text('Ver último pedido'));
    await _until(tester, find.byType(OrderConfirmationView));

    expect(find.text('Mesa 4'), findsOneWidget);
    expect(find.text('restart-order'), findsOneWidget);
    expect(secondOrders.createCalls, 0);
    expect(firstOrders.createCalls, 1);
    final confirmation = ModalRoute.of(tester.element(find.byType(OrderConfirmationView)))!;
    expect(confirmation.settings.name, AppRoutes.order);

    Navigator.of(tester.element(find.byType(OrderConfirmationView))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OrderConfirmationView), findsNothing);
    expect(find.text('dinna'), findsOneWidget);
    expect(secondOrders.createCalls, 0);

    await tester.ensureVisible(find.text('Ver último pedido'));
    await tester.tap(find.text('Ver último pedido'));
    await _until(tester, find.byType(OrderConfirmationView));
    await _flushIo(tester);
    final list = find.descendant(
      of: find.byType(OrderConfirmationView),
      matching: find.byType(ListView),
    );
    await tester.drag(list, const Offset(0, -800));
    await _flushIo(tester);
    final submission = tester
        .widget<OrderConfirmationView>(find.byType(OrderConfirmationView))
        .submission!;
    expect(submission.canBeginAnotherOrder, isTrue);
    await tester.tap(find.text('Fazer outro pedido'));
    await _until(tester, find.byType(TableView));
    for (
      var attempt = 0;
      attempt < 20 && find.byType(OrderConfirmationView).evaluate().isNotEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final tableRoute = ModalRoute.of(tester.element(find.byType(TableView)))!;
    expect(tableRoute.isCurrent, isTrue);
    expect(tableRoute.settings.name, AppRoutes.table);
    expect(
      find.byType(OrderConfirmationView),
      findsNothing,
      reason: 'rota atual ${tableRoute.settings.name}',
    );
    expect(secondOrders.createCalls, 0);

    final snapshot = await tester.runAsync(() async {
      final database = await secondDatabase.database;
      return (
        items: await database.query(DinnaDatabase.cartItemsTable),
        marks: await database.query(DinnaDatabase.reconciliationsTable),
        orders: await database.query(DinnaDatabase.lastOrdersTable),
      );
    });

    expect(snapshot, isNotNull);
    expect(snapshot!.items, hasLength(1));
    expect(snapshot.items.single['product_id'], 'p2');
    expect(snapshot.items.single['quantity'], 1);
    expect(snapshot.items.single['note'], 'fora do envio');
    expect(snapshot.marks, hasLength(1));
    expect(snapshot.orders, hasLength(1));
    expect(await secondRepository.load(), hasLength(1));
    final recovered = await tester.runAsync(
      () => SqfliteLastOrderStore(database: secondDatabase).load(),
    );
    expect(recovered, order);
  });
}

Future<void> _flushIo(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  fail('Não apareceu: $finder');
}

Widget _app({
  required DinnaDatabase database,
  required SqfliteCartRepository repository,
  required File intentFile,
  required FakeOrderRepository orders,
  CartSession? session,
}) {
  final products = FakeProductRepository(
    () async => ProductList.ready([
      Product(
        id: 'p1',
        name: 'Moqueca de Peixe',
        description: '',
        category: 'pratos',
        priceCents: 4890,
        imageUrl: null,
        available: true,
      ),
      Product(
        id: 'p2',
        name: 'Suco',
        description: '',
        category: 'bebidas',
        priceCents: 800,
        imageUrl: null,
        available: true,
      ),
    ]),
  );
  return DinnaApp(
    apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
    orderRepository: orders,
    productRepository: products,
    cartSession: session ?? CartSession(repository),
    orderIntentStore: FileOrderIntentStore(intentFile),
    lastOrderStore: SqfliteLastOrderStore(database: database),
    pollDelay: (_) async {},
  );
}
