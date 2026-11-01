import 'dart:io';

import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/features/client/order/order_intent.dart';
import 'package:dinna/features/client/order/order_intent_id.dart';
import 'package:dinna/features/client/order/order_intent_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../restaurant/sample_order.dart';

void main() {
  final createdAt = DateTime.utc(2026, 11, 1, 15);

  OrderIntent intent({OrderIntentPhase phase = OrderIntentPhase.pending}) {
    return OrderIntent(
      id: newOrderIntentId(),
      createdAt: createdAt,
      phase: phase,
      table: '12',
      items: [
        {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
        {'productId': 'p2', 'quantity': 1},
        {'productId': 'p3', 'quantity': 1, 'note': ''},
      ],
      block: phase == OrderIntentPhase.blocked ? OrderIntentBlock.expired : null,
      order: phase == OrderIntentPhase.succeeded
          ? sampleOrder(
              id: 'o1',
              items: [OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola')],
            )
          : null,
    );
  }

  test('UUID v4 gerado cabe no contrato e muda a cada chamada', () {
    final first = newOrderIntentId();
    final second = newOrderIntentId();

    expect(orderIntentIdPattern.hasMatch(first), isTrue);
    expect(first.substring(14, 15), '4');
    expect(first, isNot(second));
    expect(first, isNot('00000000-0000-0000-0000-000000000000'));
  });

  test('a folga de reenvio termina uma hora antes da retenção', () {
    final stored = intent();
    final born = stored.createdAt;

    expect(stored.allowsResume(born), isTrue);
    expect(stored.allowsResume(born.add(const Duration(hours: 22, minutes: 59))), isTrue);
    expect(
      stored.allowsResume(born.add(OrderIntent.retention - OrderIntent.resumeSafetyMargin)),
      isFalse,
    );
    expect(stored.allowsResume(born.subtract(const Duration(minutes: 1))), isFalse);
    expect(OrderIntent.retention - OrderIntent.resumeSafetyMargin, const Duration(hours: 23));
  });

  test('grava e lê de novo a mesma chave, a note vazia e a note omitida', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileOrderIntentStore(File('${directory.path}/order-intent.json'));
    final stored = intent();

    await store.save(stored);
    final loaded = await store.load();

    expect(loaded!.id, stored.id);
    expect(loaded.createdAt, createdAt);
    expect(loaded.phase, OrderIntentPhase.pending);
    expect(loaded.items[0].containsKey('note'), isTrue);
    expect(loaded.items[1].containsKey('note'), isFalse);
    expect(loaded.items[2]['note'], '');
    expect(loaded.body, stored.body);
  });

  test('arquivo corrompido permanece e a leitura seguinte continua falhando', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/order-intent.json');
    await file.writeAsString('{', flush: true);
    final store = FileOrderIntentStore(file);

    expect(
      store.load,
      throwsA(
        isA<OrderIntentStoreException>().having(
          (error) => error.problem,
          'problem',
          OrderIntentStoreProblem.corrupt,
        ),
      ),
    );
    expect(await file.readAsString(), '{');
    expect(store.load, throwsA(isA<OrderIntentStoreException>()));
  });

  test('temporário válido sem arquivo final vira a intenção recuperada', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/order-intent.json');
    final stored = intent();
    await File('${file.path}.tmp').writeAsString(
      '{"id":"${stored.id}","createdAt":"2026-11-01T15:00:00Z","phase":"pending","table":"12","items":[{"productId":"p1","quantity":2,"note":"sem cebola"},{"productId":"p2","quantity":1},{"productId":"p3","quantity":1,"note":""}]}',
      flush: true,
    );
    final store = FileOrderIntentStore(file);

    final loaded = await store.load();

    expect(loaded!.id, stored.id);
    expect(loaded.items[1].containsKey('note'), isFalse);
    expect(await file.exists(), isTrue);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('temporário incompleto não libera uma leitura vazia', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/order-intent.json');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString('{', flush: true);
    final store = FileOrderIntentStore(file);

    expect(store.load, throwsA(isA<OrderIntentStoreException>()));
    expect(await temp.exists(), isTrue);
    expect(await file.exists(), isFalse);
  });

  test('sucesso gravado volta com o pedido e a limpeza só é sinalizada por ele', () async {
    final directory = await Directory.systemTemp.createTemp('dinna-intent-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileOrderIntentStore(File('${directory.path}/order-intent.json'));
    final stored = intent(phase: OrderIntentPhase.succeeded);

    await store.save(stored);
    final loaded = await store.load();

    expect(loaded!.phase, OrderIntentPhase.succeeded);
    expect(loaded.order!.id, 'o1');
    expect(loaded.order!.items.single.quantity, 2);
    expect(loaded.cartItems.first.quantity, 2);
  });
}
