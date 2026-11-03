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
  "available": true,
  "ingredients": []
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
      expect(product.ingredients, isEmpty);
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
        'ingredients nulo': _productMap()..['ingredients'] = null,
        'ingredients texto': _productMap()..['ingredients'] = 'Pão',
        'ingredients número': _productMap()..['ingredients'] = [1],
        'ingredients string vazia': _productMap()..['ingredients'] = [''],
        'ingredients só espaços': _productMap()..['ingredients'] = ['   '],
        'ingredients espaço de largura zero': _productMap()..['ingredients'] = ['\u200B'],
        'ingredients caractere de controle': _productMap()..['ingredients'] = ['\u0000'],
        'ingredients com espaço no início': _productMap()..['ingredients'] = [' Pão'],
        'ingredients com espaço no fim': _productMap()..['ingredients'] = ['Pão '],
        'ingredients acima de 80': _productMap()..['ingredients'] = ['a' * 81],
        'ingredients acima de 30': _productMap()..['ingredients'] = List.filled(31, 'Pão'),
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

    test('lê ingredients na ordem e na grafia informadas', () {
      final product = Product.fromJson(
        _productMap()..['ingredients'] = ['Pão', 'Queijo cheddar', 'Pão'],
      );

      expect(product.ingredients, ['Pão', 'Queijo cheddar', 'Pão']);
      expect(product.description, 'Pão, blend 180g, queijo e salada');
    });

    test('faz round-trip de ingredients', () {
      final product = Product.fromJson(_productMap()..['ingredients'] = ['Pão', 'Queijo cheddar']);
      final again = Product.fromJson(jsonDecode(jsonEncode(product.toJson())) as Object);

      expect(again, product);
      expect(again.ingredients, ['Pão', 'Queijo cheddar']);
      expect(again.toJson()['ingredients'], ['Pão', 'Queijo cheddar']);
    });

    test('resposta antiga sem ingredients vira lista vazia', () {
      final json = _productMap()..remove('ingredients');
      final product = Product.fromJson(json);

      expect(product.ingredients, isEmpty);
      expect(product.toJson()['ingredients'], isEmpty);
      expect(product.priceCents, 3290);
      expect(product.available, isTrue);
    });

    test('aceita lista vazia explícita', () {
      final product = Product.fromJson(_productMap()..['ingredients'] = <String>[]);

      expect(product.ingredients, isEmpty);
      expect(product.toJson()['ingredients'], isEmpty);
    });

    test('não deixa a lista ser alterada por fora', () {
      final source = <String>['Pão'];
      final product = Product(
        id: 'p1',
        name: 'Burger',
        description: '',
        category: 'burgers',
        priceCents: 0,
        imageUrl: null,
        available: true,
        ingredients: source,
      );

      source.add('Queijo cheddar');

      expect(product.ingredients, ['Pão']);
      expect(() => product.ingredients.add('Sal'), throwsUnsupportedError);
    });

    test('considera ordem de ingredients na igualdade e no hashCode', () {
      final left = Product.fromJson(_productMap()..['ingredients'] = ['Pão', 'Queijo cheddar']);
      final same = Product.fromJson(_productMap()..['ingredients'] = ['Pão', 'Queijo cheddar']);
      final reordered = Product.fromJson(
        _productMap()..['ingredients'] = ['Queijo cheddar', 'Pão'],
      );

      expect(left, same);
      expect(left.hashCode, same.hashCode);
      expect(left, isNot(reordered));
    });

    test('conta pontos de código Unicode no limite do ingrediente', () {
      final accepted = '${'a' * 79}🥖';
      final rejected = '${'a' * 80}🥖';
      expect(accepted.runes.length, 80);
      expect(accepted.length, 81);

      final product = Product.fromJson(_productMap()..['ingredients'] = [accepted]);

      expect(product.ingredients, [accepted]);
      expect(Product.fromJson(_productMap()..['ingredients'] = ['Cogumelo 👩‍🍳']).ingredients, [
        'Cogumelo 👩‍🍳',
      ]);
      expect(
        () => Product.fromJson(_productMap()..['ingredients'] = [rejected]),
        throwsFormatException,
      );
    });

    test('construtor rejeita ingrediente em branco', () {
      expect(
        () => Product(
          id: 'p1',
          name: 'Burger',
          description: '',
          category: 'burgers',
          priceCents: 0,
          imageUrl: null,
          available: true,
          ingredients: ['   '],
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
  'ingredients': <String>[],
};

String _seedShapeWithoutImage() => jsonEncode(_productMap()..remove('imageUrl'));
