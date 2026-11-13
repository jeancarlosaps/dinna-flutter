import 'dart:convert';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/core/domain/product.dart';
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
    expect(products.first.ingredients, isEmpty);
    expect(products.last.category, 'burgers');
    expect(products.last.priceCents, 3490);
    expect(products.last.imageUrl, isNull);
    expect(products.last.available, isFalse);
    expect(products.last.ingredients, isEmpty);
    expect(result.message, isNull);
  });

  test('preserva ingredients e recusa lista inválida', () async {
    final withIngredients = {
      ..._contractProduct,
      'ingredients': ['Pão', 'Queijo cheddar'],
    };
    final listed = await repositoryReturning(
      http.Response(
        jsonEncode([withIngredients]),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    ).list();

    expect(listed.products?.single.ingredients, ['Pão', 'Queijo cheddar']);
    expect(listed.message, isNull);

    final invalid = await repositoryReturning(
      http.Response(
        jsonEncode([
          {
            ..._contractProduct,
            'ingredients': [' '],
          },
        ]),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    ).list();

    expect(invalid.products, isNull);
    expect(invalid.message, HttpProductRepository.unexpectedResponseMessage);
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
    expect(result.product?.ingredients, isEmpty);
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

  test('cria produto em POST /products e devolve o id gerado', () async {
    late http.Request requested;
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requested = request;
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({...body, 'id': 'p_novo'}),
            201,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final input = _milkshake;

    final result = await repository.create(input);

    expect(requested.method, 'POST');
    expect(requested.url.toString(), 'http://localhost:3333/products');
    expect(requested.headers['content-type'], contains('application/json'));
    expect(jsonDecode(requested.body), input.toJson());
    expect(result.product?.id, 'p_novo');
    expect(result.product?.name, 'Milkshake');
    expect(result.failure, isNull);
  });

  test('atualiza produto em PUT /products/:id', () async {
    late http.Request requested;
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requested = request;
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({...body, 'id': 'p1'}),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await repository.update(id: 'p1', input: _milkshake);

    expect(requested.method, 'PUT');
    expect(requested.url.toString(), 'http://localhost:3333/products/p1');
    expect(result.product?.priceCents, 1890);
    expect(result.product?.ingredients, isEmpty);
  });

  test('desativa produto em DELETE /products/:id sem corpo', () async {
    late http.Request requested;
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((request) async {
          requested = request;
          return http.Response('', 204);
        }),
      ),
    );

    final result = await repository.deactivate('p1');

    expect(requested.method, 'DELETE');
    expect(requested.url.toString(), 'http://localhost:3333/products/p1');
    expect(requested.body, isEmpty);
    expect(result.removed, isTrue);
    expect(result.product, isNull);
  });

  test('traduz 400 do cadastro sem chamar de novo', () async {
    var calls = 0;
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'error': {'code': 'VALIDATION_ERROR', 'message': 'Nome inválido', 'details': []},
            }),
            400,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );

    final result = await repository.create(_milkshake);

    expect(calls, 1);
    expect(result.product, isNull);
    expect(result.message, 'Nome inválido');
    expect(result.failure, DataFailure.validation);
  });

  test('queda depois do envio do cadastro fica incerta e não repete o POST', () async {
    var calls = 0;
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient((_) async {
          calls++;
          throw http.ClientException('Connection reset');
        }),
      ),
    );

    final result = await repository.create(_milkshake);

    expect(calls, 1);
    expect(result.product, isNull);
    expect(result.failure, DataFailure.uncertain);
    expect(result.message, HttpProductRepository.uncertainCreateMessage);
  });

  test('201 fora do contrato no cadastro fica incerto', () async {
    final repository = HttpProductRepository(
      ApiClient(
        baseUrl: baseUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'id': 'p_novo'}),
            201,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );

    final result = await repository.create(_milkshake);

    expect(result.failure, DataFailure.uncertain);
    expect(result.message, HttpProductRepository.uncertainCreateMessage);
  });
}

final _milkshake = ProductInput(
  name: 'Milkshake',
  description: 'Creme de baunilha',
  category: 'bebidas',
  priceCents: 1890,
  imageUrl: null,
  available: true,
);
