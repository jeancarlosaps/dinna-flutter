import 'dart:io';

import 'package:dinna/features/client/cart/cart_session.dart';
import 'package:dinna/features/client/cart/cart_view_model.dart';
import 'package:dinna/features/client/cart/sqflite_cart_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../menu/fake_product_repository.dart';

/// Sessão do carrinho sobre o SQLite real (FFI), sem dublê do repositório.
void main() {
  late Directory directory;
  late DatabaseFactory factory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dinna-cart-session-');
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

  var lineIndex = 0;
  setUp(() => lineIndex = 0);

  SqfliteCartRepository open() {
    return SqfliteCartRepository(factory: factory, lineIdGenerator: () => 'line-${++lineIndex}');
  }

  Future<CartSession> restoredSession(SqfliteCartRepository repository) async {
    final session = CartSession(repository);
    addTearDown(session.dispose);
    await session.restore();
    return session;
  }

  final ProductRepository products = FakeProductRepository(
    () async => ProductList.ready([sampleProduct(id: 'p1', name: 'Moqueca')]),
  );

  Future<void> failOn(String operation) async {
    final database = await factory.openDatabase(path.join(directory.path, 'dinna.db'));
    await database.execute('''
      CREATE TRIGGER cart_items_fail_$operation
      BEFORE $operation ON cart_items
      BEGIN
        SELECT RAISE(ABORT, 'falha forçada');
      END
    ''');
  }

  test('inclusão grava produto e quantidade e volta numa nova sessão', () async {
    final session = await restoredSession(open());

    final added = await session.addLine(productId: 'p1', quantity: 3);

    expect(added.lineId, isNotNull);
    expect(session.read(), [added]);

    final reopened = await restoredSession(open());
    final restored = reopened.read().single;
    expect(restored.lineId, added.lineId);
    expect(restored.productId, 'p1');
    expect(restored.quantity, 3);
  });

  test('incremento pendente do carrinho fechado soma com o do carrinho reaberto', () async {
    final repository = open();
    final session = await restoredSession(repository);
    await session.addLine(productId: 'p1', quantity: 1);

    final closed = CartViewModel.persisted(products, session: session);
    final pending = closed.increase(0);
    closed.dispose();

    final reopened = CartViewModel.persisted(products, session: session);
    addTearDown(reopened.dispose);
    expect(reopened.isMutating, isFalse);
    await reopened.increase(0);
    await pending;

    expect(session.read().single.quantity, 3);
    expect(reopened.rows.single.quantity, 3);
    expect((await repository.load()).single.quantity, 3);
    expect(reopened.cartWriteErrorMessage, isNull);
  });

  test('operações pendentes ficam visíveis até o SQLite responder, com sucesso ou falha', () async {
    final session = await restoredSession(open());
    expect(session.hasPendingOperations, isFalse);

    final add = session.addLine(productId: 'p1', quantity: 1);
    final increase = session.changeQuantity(lineId: 'line-1', delta: 1);
    expect(session.hasPendingOperations, isTrue);

    await add;
    expect(session.hasPendingOperations, isTrue);
    await increase;
    expect(session.hasPendingOperations, isFalse);
    expect(session.read().single.quantity, 2);

    await failOn('UPDATE');
    final failing = session.changeQuantity(lineId: 'line-1', delta: 1);
    expect(session.hasPendingOperations, isTrue);
    await expectLater(failing, throwsA(isA<DatabaseException>()));
    expect(session.hasPendingOperations, isFalse);
    expect(session.read().single.quantity, 2);
  });

  test('falha do SQLite ao atualizar mantém a quantidade confirmada', () async {
    final repository = open();
    final session = await restoredSession(repository);
    final line = await session.addLine(productId: 'p1', quantity: 2);
    final viewModel = CartViewModel.persisted(products, session: session);
    addTearDown(viewModel.dispose);
    await failOn('UPDATE');

    await viewModel.increase(0);

    expect(viewModel.cartWriteErrorMessage, isNotNull);
    expect(viewModel.isMutating, isFalse);
    expect(viewModel.rows.single.quantity, 2);
    expect(session.isReady, isTrue);
    expect(session.read(), [line]);
    expect(await repository.load(), [line]);
  });

  test('falha do SQLite ao remover mantém a linha confirmada', () async {
    final repository = open();
    final session = await restoredSession(repository);
    final line = await session.addLine(productId: 'p1', quantity: 1);
    final viewModel = CartViewModel.persisted(products, session: session);
    addTearDown(viewModel.dispose);
    await failOn('DELETE');

    await viewModel.removeAt(0);

    expect(viewModel.cartWriteErrorMessage, isNotNull);
    expect(viewModel.rows, hasLength(1));
    expect(session.read(), [line]);
    expect(await repository.load(), [line]);
  });

  test('falha do SQLite ao incluir não publica linha nem apaga as anteriores', () async {
    final repository = open();
    final session = await restoredSession(repository);
    final line = await session.addLine(productId: 'p1', quantity: 1);
    await failOn('INSERT');

    await expectLater(
      session.addLine(productId: 'p2', quantity: 2),
      throwsA(isA<DatabaseException>()),
    );

    expect(session.isReady, isTrue);
    expect(session.read(), [line]);
    expect(await repository.load(), [line]);
  });
}
