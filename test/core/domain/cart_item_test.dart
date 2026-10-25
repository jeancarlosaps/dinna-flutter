import 'dart:convert';

import 'package:dinna/core/domain/cart_item.dart';
import 'package:dinna/core/domain/order_item.dart';
import 'package:flutter_test/flutter_test.dart';

const _withNote = '{"productId":"p1","quantity":2,"note":"sem cebola"}';
const _withoutNote = '{"productId":"p2","quantity":1}';

void main() {
  group('CartItem', () {
    test('lê e grava o JSON local com observação', () {
      final item = CartItem.fromJson(jsonDecode(_withNote) as Object);

      expect(item.productId, 'p1');
      expect(item.quantity, 2);
      expect(item.note, 'sem cebola');
      expect(item.toJson(), jsonDecode(_withNote));
    });

    test('faz round-trip do item sem observação', () {
      final item = CartItem.fromJson(jsonDecode(_withoutNote) as Object);

      expect(item.note, isNull);
      expect(item.toJson().containsKey('note'), isFalse);
      expect(CartItem.fromJson(jsonDecode(jsonEncode(item.toJson())) as Object), item);
    });

    test('aceita observação de 200 caracteres e rejeita 201', () {
      final note = 'a' * 200;
      final item = CartItem.fromJson({'productId': 'p1', 'quantity': 1, 'note': note});

      expect(item.note, note);
      expect(
        () => CartItem.fromJson({'productId': 'p1', 'quantity': 1, 'note': 'a' * 201}),
        throwsFormatException,
      );
    });

    test('converte para OrderItem sem campos a mais', () {
      final item = CartItem.fromJson(jsonDecode(_withNote) as Object);
      final orderItem = item.toOrderItem();

      expect(orderItem, OrderItem(productId: 'p1', quantity: 2, note: 'sem cebola'));
      expect(item.toJson(), orderItem.toJson());
      expect(orderItem.toJson().keys, ['productId', 'quantity', 'note']);
    });

    test('converte item sem observação para o body de POST /orders', () {
      final orderItem = CartItem.fromJson(jsonDecode(_withoutNote) as Object).toOrderItem();

      expect(orderItem.toJson(), jsonDecode(_withoutNote));
    });

    test('rejeita JSON incompatível com o contrato local', () {
      final cases = <String, Object?>{
        'não é objeto': jsonDecode('[]'),
        'productId ausente': _itemMap()..remove('productId'),
        'productId vazio': _itemMap()..['productId'] = '',
        'quantity ausente': _itemMap()..remove('quantity'),
        'quantity zero': _itemMap()..['quantity'] = 0,
        'quantity fracionária': _itemMap()..['quantity'] = 1.5,
        'quantity texto': _itemMap()..['quantity'] = '2',
        'note numérica': _itemMap()..['note'] = 1,
      };

      for (final entry in cases.entries) {
        expect(() => CartItem.fromJson(entry.value), throwsFormatException, reason: entry.key);
      }
    });

    test('construtor rejeita quantidade menor que 1', () {
      expect(() => CartItem(productId: 'p1', quantity: 0, note: null), throwsArgumentError);
    });
  });
}

Map<String, Object?> _itemMap() => {'productId': 'p1', 'quantity': 2, 'note': 'sem cebola'};
