import 'json_values.dart';

const _nameMaxLength = 120;
const _descriptionMaxLength = 2000;
const _maxIngredients = 30;
const _maxIngredientLength = 80;

/// Nome curto, sem espaço nas pontas. Espaço interno e a grafia permanecem.
final _ingredientName = RegExp(r'^\S(?:.*\S)?$');

/// Produto do cardápio, no formato de resposta da API.
///
/// `priceCents` é inteiro de centavos. O body de `POST`/`PUT` não é este
/// model: lá o `id` não vai e `available` pode ser omitido.
///
/// `ingredients` é a lista ordenada de nomes. Resposta antiga, sem o campo,
/// vira lista vazia. A lista não é lida de `description`. `null`, outro tipo,
/// string vazia ou só com espaços são erro. O construtor copia a lista e a
/// deixa imutável.
final class Product {
  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.priceCents,
    required this.imageUrl,
    required this.available,
    List<String> ingredients = const [],
  }) : ingredients = List<String>.unmodifiable(ingredients) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'id deve ter ao menos 1 caractere');
    }
    if (name.isEmpty || name.length > _nameMaxLength) {
      throw ArgumentError.value(name, 'name', 'name deve ter de 1 a $_nameMaxLength caracteres');
    }
    if (description.length > _descriptionMaxLength) {
      throw ArgumentError.value(
        description,
        'description',
        'description deve ter no máximo $_descriptionMaxLength caracteres',
      );
    }
    if (category.isEmpty) {
      throw ArgumentError.value(category, 'category', 'category deve ter ao menos 1 caractere');
    }
    if (priceCents < 0) {
      throw ArgumentError.value(priceCents, 'priceCents', 'priceCents deve ser >= 0');
    }
    _requireImageUri(imageUrl);
    _requireIngredients(this.ingredients);
  }

  /// Recurso `Product` do contrato. Chave desconhecida é ignorada.
  factory Product.fromJson(Object? json) {
    return parseModel(() {
      final map = readJsonObject(json, 'Product');
      return Product(
        id: readRequiredString(map, 'id'),
        name: readRequiredString(map, 'name', maxLength: _nameMaxLength),
        description: readRequiredString(
          map,
          'description',
          minLength: 0,
          maxLength: _descriptionMaxLength,
        ),
        category: readRequiredString(map, 'category'),
        priceCents: readRequiredInt(map, 'priceCents', min: 0),
        imageUrl: readOptionalString(map, 'imageUrl'),
        available: readRequiredBool(map, 'available'),
        ingredients: _readIngredients(map),
      );
    });
  }

  final String id;
  final String name;

  /// Pode ser `""`. Não é a lista de ingredientes.
  final String description;

  /// Slug livre, por exemplo `burgers` ou `bebidas`.
  final String category;

  /// Preço em centavos. O contrato não representa dinheiro como `double`.
  final int priceCents;

  /// URI da imagem. Ausente ou `null` no JSON significa sem imagem.
  final String? imageUrl;

  /// `false` é indisponível, inclusive depois do soft-delete.
  final bool available;

  /// Nomes na ordem da API. Vazia quando a composição não veio no JSON.
  final List<String> ingredients;

  /// Omite `imageUrl` quando não há imagem. Ausência e `null` são o mesmo valor.
  /// `ingredients` sempre sai, inclusive quando a lista é vazia.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'priceCents': priceCents,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'available': available,
    'ingredients': ingredients,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Product &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.category == category &&
        other.priceCents == priceCents &&
        other.imageUrl == imageUrl &&
        other.available == available &&
        _sameStrings(other.ingredients, ingredients);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    category,
    priceCents,
    imageUrl,
    available,
    Object.hashAll(ingredients),
  );

  @override
  String toString() => 'Product(id: $id, priceCents: $priceCents, available: $available)';
}

void _requireImageUri(String? imageUrl) {
  if (imageUrl == null) return;
  final uri = Uri.tryParse(imageUrl);
  if (uri == null || !uri.hasScheme) {
    throw ArgumentError.value(imageUrl, 'imageUrl', 'imageUrl deve ser uma URI');
  }
}

void _requireIngredients(List<String> ingredients) {
  if (ingredients.length > _maxIngredients) {
    throw ArgumentError.value(
      ingredients,
      'ingredients',
      'ingredients deve ter no máximo $_maxIngredients itens',
    );
  }
  for (var index = 0; index < ingredients.length; index++) {
    final item = ingredients[index];
    if (item.length > _maxIngredientLength || !_ingredientName.hasMatch(item)) {
      throw ArgumentError.value(
        item,
        'ingredients[$index]',
        'ingredients[$index] deve ser um nome de 1 a $_maxIngredientLength caracteres, sem espaço nas pontas',
      );
    }
  }
}

/// Campo ausente é lista vazia. `null` e tipo diferente não são convertidos.
List<String> _readIngredients(Map<String, Object?> json) {
  if (!json.containsKey('ingredients')) return const [];

  final value = json['ingredients'];
  if (value is! List) {
    throw FormatException('Campo ingredients deve ser uma lista');
  }
  if (value.length > _maxIngredients) {
    throw FormatException('Campo ingredients deve ter no máximo $_maxIngredients itens');
  }

  final items = <String>[];
  for (var index = 0; index < value.length; index++) {
    final item = value[index];
    if (item is! String) {
      throw FormatException('Campo ingredients[$index] deve ser string');
    }
    items.add(item);
  }
  return items;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
