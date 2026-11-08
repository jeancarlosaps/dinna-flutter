import 'dart:io';

import 'package:dinna/app/app.dart';
import 'package:dinna/app/router/app_router.dart';
import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/product.dart';
import 'package:dinna/core/storage/dinna_database.dart';
import 'package:dinna/features/client/cart/cart_lines.dart';
import 'package:dinna/features/client/order/last_order_store.dart';
import 'package:dinna/features/client/order/order_confirmation_view.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../home/fake_api_status_repository.dart';
import '../../menu/fake_product_repository.dart';
import '../../restaurant/fake_order_repository.dart' show FakeOrderRepository, pendingPollDelay;
import '../../restaurant/sample_order.dart';

void main() {
  late Directory directory;
  final openedDatabases = <Database>[];

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dinna-last-order-app-');
    await databaseFactoryFfi.setDatabasesPath(directory.path);
    openedDatabases.clear();
  });

  tearDown(() async {
    for (final database in openedDatabases) {
      if (database.isOpen) await database.close();
    }
    try {
      await databaseFactoryFfi.deleteDatabase(
        path.join(directory.path, DinnaDatabase.databaseName),
      );
    } on Object {
      // O diretório temporário remove o arquivo se o factory já o fechou.
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets('último pedido confirmado é mostrado pela nova sessão do app', (tester) async {
    final order = sampleOrder(id: 'restart-order', table: '4');
    final firstDatabase = DinnaDatabase(factory: databaseFactoryFfi);
    final firstLastOrderStore = MemoryLastOrderStore();
    final firstApp = _app(
      lastOrderStore: firstLastOrderStore,
      lines: ProcessCartLines([CartItem(productId: 'p1', quantity: 1, note: null)]),
      createOrder: ({required table, required items}) async {
        expect(table, '12');
        expect(items.single.productId, 'p1');
        return OrderSubmission.created(order);
      },
    );
    await tester.pumpWidget(firstApp);
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('dinna'))).pushNamed(AppRoutes.cart, arguments: '12');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enviar pedido'));
    await tester.tap(find.text('Enviar pedido'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('restart-order'), findsOneWidget);
    expect(await firstLastOrderStore.load(), order);
    await tester.pumpWidget(const SizedBox.shrink());

    Database? firstHandle;
    await tester.runAsync(() async {
      firstHandle = await firstDatabase.database;
      await SqfliteLastOrderStore(database: firstDatabase).save(order);
    });
    openedDatabases.add(firstHandle!);
    await tester.runAsync(firstHandle!.close);

    final restartedDatabase = DinnaDatabase(factory: databaseFactoryFfi);
    final restartedHandle = await tester.runAsync(() => restartedDatabase.database);
    expect(restartedHandle, isNotNull);
    openedDatabases.add(restartedHandle!);
    final recoveredOrder = await tester.runAsync(
      () => SqfliteLastOrderStore(database: restartedDatabase).load(),
    );
    expect(recoveredOrder, order);
    final recoveredStore = MemoryLastOrderStore();
    await recoveredStore.save(recoveredOrder!);

    await tester.pumpWidget(_app(lastOrderStore: recoveredStore, lines: ProcessCartLines()));
    await tester.pumpAndSettle();

    expect(find.text('Mesa 4 · restart-order'), findsOneWidget);
    await tester.tap(find.text('Ver último pedido'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderConfirmationView), findsOneWidget);
    expect(find.text('Mesa 4'), findsOneWidget);
    expect(find.text('restart-order'), findsOneWidget);
  });
}

Widget _app({
  required LastOrderStore lastOrderStore,
  required CartLines lines,
  Future<OrderSubmission> Function({required String table, required List<CartItem> items})?
  createOrder,
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
    ]),
  );
  return DinnaApp(
    apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
    orderRepository: FakeOrderRepository(
      () async => OrderList.ready(const []),
      onCreate:
          createOrder ??
          ({required table, required items}) async =>
              OrderSubmission.created(sampleOrder(id: 'unused')),
    ),
    productRepository: products,
    cartLines: lines,
    lastOrderStore: lastOrderStore,
    pollDelay: pendingPollDelay,
  );
}
