import 'json_values.dart';

const _nameMaxLength = 120;
const _descriptionMaxLength = 2000;

/// Produto do cardápio, no formato de resposta da API.
///
/// `priceCents` é inteiro de centavos. O body de `POST`/`PUT` não é este
/// model: lá o `id` não vai e `available` pode ser omitido.
final class Product {
  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.priceCents,
    required this.imageUrl,
    required this.available,
  }) {
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
      );
    });
  }

  final String id;
  final String name;

  /// Pode ser `""`.
  final String description;

  /// Slug livre, por exemplo `burgers` ou `bebidas`.
  final String category;

  /// Preço em centavos. O contrato não representa dinheiro como `double`.
  final int priceCents;

  /// URI da imagem. Ausente ou `null` no JSON significa sem imagem.
  final String? imageUrl;

  /// `false` é indisponível, inclusive depois do soft-delete.
  final bool available;

  /// Omite `imageUrl` quando não há imagem. Ausência e `null` são o mesmo valor.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'priceCents': priceCents,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'available': available,
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
        other.available == available;
  }

  @override
  int get hashCode => Object.hash(id, name, description, category, priceCents, imageUrl, available);

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
