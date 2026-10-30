import 'dart:convert';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/network/api_client.dart';
import 'package:dinna/features/menu/http_product_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Exemplo de `Product` em docs/api-contract.md (dinna-api, SCRUM-24).
const _contractProduct = {
  'id': 'p1',
  'name': 'Burger Clássico',
  'description': 'Pão, blend 180g, queijo e salada',
  'category': 'burgers',
  'priceCents': 3290,
  'imageUrl': 'https://example.com/burger.jpg',
  'available': true,
};

/// Produto `p8` do seed da API: sem imagem e indisponível.
const _seedUnavailable = {
  'id': 'p8',
  'name': 'Burger Veggie',
  'description': 'Hambúrguer de grão-de-bico, queijo e salada',
  'category': 'burgers',
  'priceCents': 3490,
  'imageUrl': null,
  'available': false,
};

void main() {
  final baseUrl = Uri.parse('http://localhost:3333');

  HttpProductRepository repositoryReturning(http.Response response) {
    return HttpProductRepository(
      ApiClient(baseUrl: baseUrl, httpClient: MockClient((_) async => response)),
    );
  }

  test('lista produtos válidos em GET /products', () async {
    late Uri requested;
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode([_contractProduct]),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await repository.list();

    expect(requested.toString(), 'http://localhost:3333/products');
    expect(requested.query, isEmpty);
    expect(result.message, isNull);
    expect(result.products, hasLength(1));
    expect(result.products!.single.id, 'p1');
    expect(result.products!.single.name, 'Burger Clássico');
  });

  test('preserva categoria, centavos, imagem e disponibilidade', () async {
    final repository = repositoryReturning(
      http.Response(
        jsonEncode([_contractProduct, _seedUnavailable]),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final result = await repository.list();
    final products = result.products!;

    expect(products, hasLength(2));
    expect(products.first.category, 'burgers');
    expect(products.first.priceCents, 3290);
    expect(products.first.priceCents, isA<int>());
    expect(products.first.imageUrl, 'https://example.com/burger.jpg');
    expect(products.first.available, isTrue);
    expect(products.last.category, 'burgers');
    expect(products.last.priceCents, 3490);
    expect(products.last.imageUrl, isNull);
    expect(products.last.available, isFalse);
    expect(result.message, isNull);
  });

  test('aceita lista vazia como cardápio sem itens', () async {
    final repository = repositoryReturning(
      http.Response('[]', 200, headers: const {'content-type': 'application/json; charset=utf-8'}),
    );

    final result = await repository.list();

    expect(result.products, isEmpty);
    expect(result.message, isNull);
  });

  test('traduz JSON incompatível com a lista do contrato', () async {
    final objectBody = repositoryReturning(
      http.Response(
        jsonEncode({
          'products': [_contractProduct],
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final invalidItem = repositoryReturning(
      http.Response(
        jsonEncode([
          {'id': 'p1', 'name': 'Burger Clássico'},
        ]),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final wrapped = await objectBody.list();
    final brokenItem = await invalidItem.list();

    expect(wrapped.products, isNull);
    expect(wrapped.message, HttpProductRepository.unexpectedResponseMessage);
    expect(brokenItem.products, isNull);
    expect(brokenItem.message, HttpProductRepository.unexpectedResponseMessage);
  });

  test('traduz resposta HTTP inválida na mensagem da API', () async {
    final repository = repositoryReturning(
      http.Response(
        jsonEncode({
          'error': {'code': 'UNAVAILABLE', 'message': 'API em manutenção'},
        }),
        503,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final result = await repository.list();

    expect(result.products, isNull);
    expect(result.message, 'API em manutenção');
    expect(result.failure, DataFailure.unavailable);
  });

  test('diferencia validação, ausência e conflito', () async {
    Future<ProductList> failed(int status, String message) {
      return repositoryReturning(
        http.Response(
          jsonEncode({
            'error': {'code': 'X', 'message': message},
          }),
          status,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ).list();
    }

    final validation = await failed(400, 'Consulta inválida');
    final missing = await failed(404, 'Produto não encontrado');
    final conflict = await failed(409, 'Conflito');

    expect(validation.message, 'Consulta inválida');
    expect(validation.failure, DataFailure.validation);
    expect(validation.products, isNull);
    expect(missing.failure, DataFailure.notFound);
    expect(conflict.failure, DataFailure.conflict);
  });

  test('traduz erro de rede na mensagem do Service', () async {
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async => throw http.ClientException('Connection refused')),
      ),
    );

    final result = await repository.list();

    expect(result.products, isNull);
    expect(result.message, 'Não foi possível conectar à API');
    expect(result.message, isNot(contains('Connection refused')));
    expect(result.failure, DataFailure.unavailable);
    expect(result.detail, 'Connection refused');
  });

  test('busca o produto em GET /products/:id', () async {
    late Uri requested;
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode(_contractProduct),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await repository.findById('p1');

    expect(requested.toString(), 'http://localhost:3333/products/p1');
    expect(result.product?.id, 'p1');
    expect(result.product?.name, 'Burger Clássico');
    expect(result.product?.priceCents, 3290);
    expect(result.product?.available, isTrue);
    expect(result.message, isNull);
    expect(result.failure, isNull);
  });

  test('produto indisponível em GET /products/:id continua sendo sucesso', () async {
    final repository = repositoryReturning(
      http.Response(
        jsonEncode(_seedUnavailable),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final result = await repository.findById('p8');

    expect(result.product?.id, 'p8');
    expect(result.product?.available, isFalse);
    expect(result.message, isNull);
    expect(result.failure, isNull);
  });

  test('traduz 404 de GET /products/:id como produto ausente', () async {
    final repository = repositoryReturning(
      http.Response(
        jsonEncode({
          'error': {'code': 'PRODUCT_NOT_FOUND', 'message': 'Produto p9 não encontrado'},
        }),
        404,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final result = await repository.findById('p9');

    expect(result.product, isNull);
    expect(result.message, 'Produto p9 não encontrado');
    expect(result.failure, DataFailure.notFound);
    expect(result.detail, isNull);
  });

  test('traduz JSON incompatível com o produto do contrato', () async {
    final listBody = repositoryReturning(
      http.Response(
        jsonEncode([_contractProduct]),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final brokenProduct = repositoryReturning(
      http.Response(
        jsonEncode({'id': 'p1', 'name': 'Burger Clássico'}),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final wrapped = await listBody.findById('p1');
    final broken = await brokenProduct.findById('p1');

    expect(wrapped.product, isNull);
    expect(wrapped.message, HttpProductRepository.unexpectedResponseMessage);
    expect(wrapped.failure, DataFailure.unavailable);
    expect(broken.product, isNull);
    expect(broken.message, HttpProductRepository.unexpectedResponseMessage);
  });

  test('rejeita id vazio sem chamar a API', () async {
    var calls = 0;
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      ),
    );

    final result = await repository.findById('');

    expect(calls, 0);
    expect(result.product, isNull);
    expect(result.message, 'Identificador do produto inválido');
    expect(result.failure, DataFailure.validation);
  });

  test('traduz erro de rede de GET /products/:id na mensagem do Service', () async {
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async => throw http.ClientException('Connection refused')),
      ),
    );

    final result = await repository.findById('p1');

    expect(result.product, isNull);
    expect(result.message, 'Não foi possível conectar à API');
    expect(result.message, isNot(contains('Connection refused')));
    expect(result.failure, DataFailure.unavailable);
    expect(result.detail, 'Connection refused');
  });
}
