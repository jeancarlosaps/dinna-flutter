import 'dart:convert';

import 'package:dinna/core/domain/order_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Item com observação, exemplo de `OrderItem` no contrato.
const _withNote = '{"productId":"p1","quantity":2,"note":"sem cebola"}';

/// Segundo item do `POST /orders`: sem `note`.
const _withoutNote = '{"productId":"p2","quantity":1}';

void main() {
  group('OrderItem', () {
    test('lê o item com observação', () {
      final item = OrderItem.fromJson(jsonDecode(_withNote) as Object);

      expect(item.productId, 'p1');
      expect(item.quantity, 2);
      expect(item.quantity, isA<int>());
      expect(item.note, 'sem cebola');
    });

    test('grava o item com observação', () {
      final item = OrderItem.fromJson(jsonDecode(_withNote) as Object);

      expect(item.toJson(), jsonDecode(_withNote));
    });

    test('faz round-trip do item sem observação', () {
      final item = OrderItem.fromJson(jsonDecode(_withoutNote) as Object);

      expect(item.note, isNull);
      expect(item.toJson().containsKey('note'), isFalse);
      expect(item.toJson(), jsonDecode(_withoutNote));
      expect(OrderItem.fromJson(jsonDecode(jsonEncode(item.toJson())) as Object), item);
    });

    test('trata note nula como ausente na saída', () {
      final item = OrderItem.fromJson(jsonDecode('$_withoutNoteBase, "note": null}'));

      expect(item.note, isNull);
      expect(item.toJson(), jsonDecode(_withoutNote));
    });

    test('aceita note vazia e a preserva', () {
      final item = OrderItem.fromJson(_itemMap()..['note'] = '');

      expect(item.note, isEmpty);
      expect(item.toJson()['note'], isEmpty);
    });

    test('rejeita JSON incompatível com o contrato', () {
      final cases = <String, Object?>{
        'não é objeto': jsonDecode('[]'),
        'productId ausente': _itemMap()..remove('productId'),
        'productId vazio': _itemMap()..['productId'] = '',
        'quantity ausente': _itemMap()..remove('quantity'),
        'quantity zero': _itemMap()..['quantity'] = 0,
        'quantity fracionária': _itemMap()..['quantity'] = 1.5,
        'quantity texto': _itemMap()..['quantity'] = '2',
        'note numérica': _itemMap()..['note'] = 1,
        'note acima de 200': _itemMap()..['note'] = 'a' * 201,
      };

      for (final entry in cases.entries) {
        expect(() => OrderItem.fromJson(entry.value), throwsFormatException, reason: entry.key);
      }
    });

    test('construtor rejeita quantidade menor que 1', () {
      expect(() => OrderItem(productId: 'p1', quantity: 0, note: null), throwsArgumentError);
    });
  });
}

const _withoutNoteBase = '{"productId":"p2","quantity":1';

Map<String, Object?> _itemMap() => {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'};
