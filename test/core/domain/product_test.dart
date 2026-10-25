import 'dart:convert';

import 'package:dinna/core/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exemplo de `Product` em docs/api-contract.md (dinna-api, SCRUM-24).
const _contractProduct = '''
{
  "id": "p1",
  "name": "Burger Clássico",
  "description": "Pão, blend 180g, queijo e salada",
  "category": "burgers",
  "priceCents": 3290,
  "imageUrl": "https://example.com/burger.jpg",
  "available": true
}
''';

/// Produto `p8` do seed da API: sem imagem e indisponível.
const _seedUnavailable = '''
{
  "id": "p8",
  "name": "Burger Veggie",
  "description": "Hambúrguer de grão-de-bico, queijo e salada",
  "category": "burgers",
  "priceCents": 3490,
  "imageUrl": null,
  "available": false
}
''';

void main() {
  group('Product', () {
    test('lê o JSON do contrato', () {
      final product = Product.fromJson(jsonDecode(_contractProduct) as Object);

      expect(product.id, 'p1');
      expect(product.name, 'Burger Clássico');
      expect(product.description, 'Pão, blend 180g, queijo e salada');
      expect(product.category, 'burgers');
      expect(product.priceCents, 3290);
      expect(product.priceCents, isA<int>());
      expect(product.imageUrl, 'https://example.com/burger.jpg');
      expect(product.available, isTrue);
    });

    test('grava o JSON do contrato', () {
      final product = Product.fromJson(jsonDecode(_contractProduct) as Object);

      expect(product.toJson(), jsonDecode(_contractProduct));
    });

    test('faz round-trip pelo texto JSON', () {
      final product = Product.fromJson(jsonDecode(_contractProduct) as Object);
      final again = Product.fromJson(jsonDecode(jsonEncode(product.toJson())) as Object);

      expect(again, product);
    });

    test('aceita imageUrl nula do seed e omite a chave na saída', () {
      final product = Product.fromJson(jsonDecode(_seedUnavailable) as Object);

      expect(product.imageUrl, isNull);
      expect(product.available, isFalse);
      expect(product.priceCents, 3490);
      expect(product.toJson().containsKey('imageUrl'), isFalse);
    });

    test('trata imageUrl ausente como sem imagem', () {
      final json = _productMap()..remove('imageUrl');
      final product = Product.fromJson(json);

      expect(product.imageUrl, isNull);
      expect(product, Product.fromJson(jsonDecode(_seedShapeWithoutImage()) as Object));
      expect(product.toJson().containsKey('imageUrl'), isFalse);
    });

    test('aceita description vazia e preço zero', () {
      final product = Product.fromJson(
        _productMap()
          ..['description'] = ''
          ..['priceCents'] = 0
          ..['imageUrl'] = null,
      );

      expect(product.description, isEmpty);
      expect(product.priceCents, 0);
    });

    test('ignora chave que o contrato não define', () {
      final product = Product.fromJson(_productMap()..['sku'] = 'burger-classico');

      expect(product.toJson().containsKey('sku'), isFalse);
      expect(product.name, 'Burger Clássico');
    });

    test('rejeita JSON incompatível com o contrato', () {
      final cases = <String, Object?>{
        'não é objeto': jsonDecode('[]'),
        'name ausente': _productMap()..remove('name'),
        'name nulo': _productMap()..['name'] = null,
        'name vazio': _productMap()..['name'] = '',
        'name acima de 120': _productMap()..['name'] = 'a' * 121,
        'name numérico': _productMap()..['name'] = 1,
        'description ausente': _productMap()..remove('description'),
        'description acima de 2000': _productMap()..['description'] = 'a' * 2001,
        'category vazia': _productMap()..['category'] = '',
        'priceCents ausente': _productMap()..remove('priceCents'),
        'priceCents texto': _productMap()..['priceCents'] = '3290',
        'priceCents fracionário': _productMap()..['priceCents'] = 32.9,
        'priceCents com casa .0': _productMap()..['priceCents'] = 3290.0,
        'priceCents negativo': _productMap()..['priceCents'] = -1,
        'available ausente': _productMap()..remove('available'),
        'available numérico': _productMap()..['available'] = 1,
        'imageUrl inválida': _productMap()..['imageUrl'] = 'burger.jpg',
        'imageUrl numérica': _productMap()..['imageUrl'] = 1,
      };

      for (final entry in cases.entries) {
        expect(() => Product.fromJson(entry.value), throwsFormatException, reason: entry.key);
      }
    });

    test('explica centavos que não são inteiros', () {
      expect(
        () => Product.fromJson(_productMap()..['priceCents'] = 32.9),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('priceCents'),
          ),
        ),
      );
    });

    test('construtor rejeita nome vazio', () {
      expect(
        () => Product(
          id: 'p1',
          name: '',
          description: '',
          category: 'burgers',
          priceCents: 0,
          imageUrl: null,
          available: true,
        ),
        throwsArgumentError,
      );
    });
  });
}

Map<String, Object?> _productMap() => {
  'id': 'p1',
  'name': 'Burger Clássico',
  'description': 'Pão, blend 180g, queijo e salada',
  'category': 'burgers',
  'priceCents': 3290,
  'imageUrl': 'https://example.com/burger.jpg',
  'available': true,
};

String _seedShapeWithoutImage() => jsonEncode(_productMap()..remove('imageUrl'));
