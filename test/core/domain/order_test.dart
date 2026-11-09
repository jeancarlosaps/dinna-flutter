import 'dart:convert';

import 'package:dinna/core/domain/order.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:dinna/core/domain/order_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exemplo de `Order` em docs/api-contract.md.
const _contractOrder = '''
{
  "id": "o1",
  "table": "12",
  "status": "received",
  "items": [{ "productId": "p1", "quantity": 2, "note": "sem cebola" }],
  "totalCents": 6580,
  "createdAt": "2026-10-16T18:00:00Z"
}
''';

/// Body de `POST /orders` acrescido dos campos que a API devolve.
/// `totalCents` é 1 de propósito: o model não recalcula a soma.
const _twoItems = '''
{
  "id": "o1",
  "table": "12",
  "status": "received",
  "items": [
    { "productId": "p1", "quantity": 2, "note": "sem cebola" },
    { "productId": "p2", "quantity": 1 }
  ],
  "totalCents": 1,
  "createdAt": "2026-10-16T18:00:00Z"
}
''';

void main() {
  group('Order', () {
    test('lê o JSON do contrato', () {
      final order = Order.fromJson(jsonDecode(_contractOrder) as Object);

      expect(order.id, 'o1');
      expect(order.table, '12');
      expect(order.status, OrderStatus.received);
      expect(order.items, hasLength(1));
      expect(order.items.single, OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola'));
      expect(order.totalCents, 6580);
      expect(order.totalCents, isA<int>());
      expect(order.createdAt, DateTime.utc(2026, 10, 16, 18));
      expect(order.createdAt.isUtc, isTrue);
      expect(order.orderNumber, isNull);
    });

    test('lê orderNumber e o omite quando está ausente', () {
      final numbered = Order.fromJson(_orderMap()..['orderNumber'] = 5);
      final absent = Order.fromJson(_orderMap());
      final explicitNull = Order.fromJson(_orderMap()..['orderNumber'] = null);

      expect(numbered.orderNumber, 5);
      expect(numbered.toJson()['orderNumber'], 5);
      expect(absent.orderNumber, isNull);
      expect(absent.toJson().containsKey('orderNumber'), isFalse);
      expect(explicitNull.orderNumber, isNull);
      expect(explicitNull.toJson(), absent.toJson());
      expect(numbered.withOrderNumber(5), same(numbered));
      expect(absent.withOrderNumber(5), numbered);
    });

    test('grava o JSON do contrato', () {
      final order = Order.fromJson(jsonDecode(_contractOrder) as Object);

      expect(order.toJson(), jsonDecode(_contractOrder));
    });

    test('faz round-trip pelo texto JSON', () {
      final order = Order.fromJson(jsonDecode(_contractOrder) as Object);
      final again = Order.fromJson(jsonDecode(jsonEncode(order.toJson())) as Object);

      expect(again, order);
    });

    test('lê lista aninhada e não recalcula totalCents', () {
      final order = Order.fromJson(jsonDecode(_twoItems) as Object);

      expect(order.items, [
        OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola'),
        OrderItem(productId: 'p2', quantity: 1, note: null),
      ]);
      expect(order.items[1].toJson().containsKey('note'), isFalse);
      expect(order.totalCents, 1);
      expect(order.toJson(), jsonDecode(_twoItems));
    });

    test('normaliza fração .000 e preserva milissegundos', () {
      final withMillis = Order.fromJson(_orderMap()..['createdAt'] = '2026-10-16T18:00:00.120Z');
      expect(withMillis.toJson()['createdAt'], '2026-10-16T18:00:00.120Z');

      final canonical = Order.fromJson(_orderMap()..['createdAt'] = '2026-10-16T18:00:00.000Z');
      expect(canonical.toJson()['createdAt'], '2026-10-16T18:00:00Z');
      expect(canonical.createdAt, DateTime.utc(2026, 10, 16, 18));
    });

    test('a lista de itens não aceita alteração', () {
      final order = Order.fromJson(jsonDecode(_contractOrder) as Object);

      expect(
        () => order.items.add(OrderItem(productId: 'p2', quantity: 1, note: null)),
        throwsUnsupportedError,
      );
    });

    test('não acompanha mutação da lista recebida no construtor', () {
      final source = [OrderItem(productId: 'p1', quantity: 1, note: null)];
      final order = Order(
        id: 'o1',
        table: '12',
        status: OrderStatus.received,
        items: source,
        totalCents: 3290,
        createdAt: DateTime.utc(2026, 10, 16, 18),
      );

      source.clear();

      expect(order.items, hasLength(1));
    });

    test('preserva snapshot dos itens quando a resposta omite name e preços', () {
      final previous = Order(
        id: 'o1',
        table: '12',
        status: OrderStatus.received,
        items: [
          OrderItem(
            productId: 'p1',
            quantity: 2,
            note: 'sem cebola',
            name: 'Burger Clássico',
            unitPriceCents: 3290,
            lineTotalCents: 6580,
          ),
        ],
        totalCents: 6580,
        createdAt: DateTime.utc(2026, 10, 16, 18),
      );
      final updated = Order(
        id: 'o1',
        table: '12',
        status: OrderStatus.preparing,
        items: [OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola')],
        totalCents: 6580,
        createdAt: DateTime.utc(2026, 10, 16, 18),
      );

      final merged = updated.preservingItemSnapshotsFrom(previous);

      expect(merged.status, OrderStatus.preparing);
      expect(merged.items.single.name, 'Burger Clássico');
      expect(merged.items.single.unitPriceCents, 3290);
      expect(merged.items.single.lineTotalCents, 6580);
    });

    test('cruza linhas do mesmo produto pela quantidade e pela observação', () {
      final previous = Order(
        id: 'o1',
        orderNumber: 5,
        table: '12',
        status: OrderStatus.received,
        items: [
          OrderItem(
            productId: 'p1',
            quantity: 2,
            note: 'sem cebola',
            name: 'Burger',
            unitPriceCents: 1000,
            lineTotalCents: 2000,
          ),
          OrderItem(
            productId: 'p1',
            quantity: 1,
            note: null,
            name: 'Burger',
            unitPriceCents: 1000,
            lineTotalCents: 1000,
          ),
        ],
        totalCents: 3000,
        createdAt: DateTime.utc(2026, 10, 16, 18),
      );
      final updated = Order(
        id: 'o1',
        table: '12',
        status: OrderStatus.preparing,
        items: [
          OrderItem(productId: 'p1', quantity: 1, note: null),
          OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola'),
        ],
        totalCents: 3000,
        createdAt: DateTime.utc(2026, 10, 16, 18),
      );

      final merged = updated.preservingItemSnapshotsFrom(previous);

      expect(merged.orderNumber, 5);
      expect(merged.status, OrderStatus.preparing);
      expect(merged.items[0].lineTotalCents, 1000);
      expect(merged.items[1].lineTotalCents, 2000);
      expect(merged.items[0].quantity, 1);
      expect(merged.items[1].quantity, 2);
    });

    test('rejeita JSON incompatível com o contrato', () {
      final cases = <String, Object?>{
        'não é objeto': jsonDecode('null'),
        'id ausente': _orderMap()..remove('id'),
        'table vazia': _orderMap()..['table'] = '',
        'status ausente': _orderMap()..remove('status'),
        'status numérico': _orderMap()..['status'] = 1,
        'status desconhecido': _orderMap()..['status'] = 'cancelled',
        'status com maiúscula': _orderMap()..['status'] = 'Received',
        'items ausente': _orderMap()..remove('items'),
        'items vazio': _orderMap()..['items'] = <Object?>[],
        'item que não é objeto': _orderMap()..['items'] = <Object?>['p1'],
        'item sem productId': _orderMap()
          ..['items'] = <Object?>[
            {'quantity': 1},
          ],
        'totalCents ausente': _orderMap()..remove('totalCents'),
        'totalCents fracionário': _orderMap()..['totalCents'] = 65.80,
        'totalCents negativo': _orderMap()..['totalCents'] = -1,
        'createdAt ausente': _orderMap()..remove('createdAt'),
        'createdAt inválida': _orderMap()..['createdAt'] = '2026-10-16T18:00:00.Z',
        'createdAt sem fuso': _orderMap()..['createdAt'] = '2026-10-16T18:00:00',
        'createdAt com offset': _orderMap()..['createdAt'] = '2026-10-16T15:00:00-03:00',
        'createdAt com z minúsculo': _orderMap()..['createdAt'] = '2026-10-16T18:00:00z',
        'orderNumber zero': _orderMap()..['orderNumber'] = 0,
        'orderNumber negativo': _orderMap()..['orderNumber'] = -1,
        'orderNumber fracionário': _orderMap()..['orderNumber'] = 1.5,
        'orderNumber texto': _orderMap()..['orderNumber'] = '0005',
      };

      for (final entry in cases.entries) {
        expect(() => Order.fromJson(entry.value), throwsFormatException, reason: entry.key);
      }
    });

    test('rejeita createdAt com z minúsculo', () {
      expect(
        () => Order.fromJson(_orderMap()..['createdAt'] = '2026-10-16T18:00:00z'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('ISO-8601 UTC'),
          ),
        ),
      );
    });

    test('nomeia status desconhecido', () {
      expect(
        () => Order.fromJson(_orderMap()..['status'] = 'cancelled'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('desconhecido'),
          ),
        ),
      );
    });

    test('construtor rejeita pedido sem itens', () {
      expect(
        () => Order(
          id: 'o1',
          table: '12',
          status: OrderStatus.received,
          items: const [],
          totalCents: 0,
          createdAt: DateTime.utc(2026, 10, 16, 18),
        ),
        throwsArgumentError,
      );
    });

    test('construtor rejeita data local', () {
      expect(
        () => Order(
          id: 'o1',
          table: '12',
          status: OrderStatus.received,
          items: [OrderItem(productId: 'p1', quantity: 1, note: null)],
          totalCents: 0,
          createdAt: DateTime(2026, 10, 16, 18),
        ),
        throwsArgumentError,
      );
    });
  });

  group('OrderStatus', () {
    test('só avança um passo do ciclo', () {
      expect(OrderStatus.received.canTransitionTo(OrderStatus.preparing), isTrue);
      expect(OrderStatus.preparing.canTransitionTo(OrderStatus.ready), isTrue);
      expect(OrderStatus.ready.canTransitionTo(OrderStatus.finished), isTrue);
      expect(OrderStatus.received.canTransitionTo(OrderStatus.ready), isFalse);
      expect(OrderStatus.preparing.canTransitionTo(OrderStatus.received), isFalse);
      expect(OrderStatus.finished.canTransitionTo(OrderStatus.ready), isFalse);
    });

    test('aponta o próximo status ou null no fim', () {
      expect(OrderStatus.received.next, OrderStatus.preparing);
      expect(OrderStatus.preparing.next, OrderStatus.ready);
      expect(OrderStatus.ready.next, OrderStatus.finished);
      expect(OrderStatus.finished.next, isNull);
    });

    test('rejeita valor fora do contrato', () {
      expect(() => OrderStatus.parse('delivered'), throwsFormatException);
      expect(OrderStatus.parse('finished'), OrderStatus.finished);
    });
  });
}

Map<String, Object?> _orderMap() => {
  'id': 'o1',
  'table': '12',
  'status': 'received',
  'items': [
    {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'},
  ],
  'totalCents': 6580,
  'createdAt': '2026-10-16T18:00:00Z',
};
