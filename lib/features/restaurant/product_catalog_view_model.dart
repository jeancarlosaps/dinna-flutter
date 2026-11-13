import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/domain/data_failure.dart';
import '../../core/domain/product.dart';
import '../menu/product_repository.dart';

/// Estado da lista de produtos do restaurante.
enum ProductCatalogStatus { loading, ready, failed }

/// Cardápio gerido pelo restaurante: lista, cadastro, edição e soft-delete.
///
/// A View não chama HTTP. O preço entra como texto (`32,90`) e só vira
/// `priceCents` aqui. Depois do [dispose], a resposta pendente não altera estado.
class ProductCatalogViewModel extends ChangeNotifier {
  ProductCatalogViewModel(this._repository);

  final ProductRepository _repository;

  static const loadError = 'Não foi possível carregar os produtos';
  static const saveError = 'Não foi possível salvar o produto';
  static const deactivateError = 'Não foi possível desativar o produto';
  static const nameError = 'O nome deve ter de 1 a 120 caracteres';
  static const descriptionError = 'A descrição deve ter no máximo 2000 caracteres';
  static const categoryError = 'Informe a categoria, como burgers';
  static const priceError = 'Informe o preço como 32,90';
  static const imageError = 'A imagem deve ser um link';
  static const ingredientsError = 'Revise os ingredientes: até 30 nomes, sem espaço nas pontas';

  ProductCatalogStatus _status = ProductCatalogStatus.loading;
  List<Product> _products = const [];
  String? _errorMessage;
  DataFailure? _failure;
  bool _saving = false;
  bool _disposed = false;
  int _loadGeneration = 0;

  ProductCatalogStatus get status => _status;
  List<Product> get products => _products;
  String? get errorMessage => _errorMessage;
  DataFailure? get failure => _failure;
  bool get isSaving => _saving;
  bool get isEmpty => _status == ProductCatalogStatus.ready && _products.isEmpty;

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    _status = ProductCatalogStatus.loading;
    _errorMessage = null;
    _failure = null;
    _notify();

    ProductList result;
    try {
      result = await _repository.list();
    } catch (_) {
      result = const ProductList.unavailable(loadError);
    }
    if (_disposed || generation != _loadGeneration) return;

    final products = result.products;
    if (products == null) {
      _status = ProductCatalogStatus.failed;
      _errorMessage = _visible(result.message, loadError);
      _failure = result.failure ?? DataFailure.unavailable;
    } else {
      _status = ProductCatalogStatus.ready;
      _products = products;
      _errorMessage = null;
      _failure = null;
    }
    _notify();
  }

  /// `null` quando o produto foi gravado. O texto é validação ou falha da API.
  Future<String?> save({
    String? id,
    required String name,
    required String description,
    required String category,
    required String priceText,
    required String imageText,
    required String ingredientsText,
    required bool available,
  }) async {
    if (_disposed || _saving) return null;
    final draft = _draft(
      name: name,
      description: description,
      category: category,
      priceText: priceText,
      imageText: imageText,
      ingredientsText: ingredientsText,
      available: available,
    );
    if (draft is String) return draft;
    final input = draft as ProductInput;

    _saving = true;
    _notify();
    try {
      final result = id == null
          ? await _repository.create(input)
          : await _repository.update(id: id, input: input);
      if (_disposed) return null;
      final product = result.product;
      if (product == null) {
        // Cadastro incerto: recarrega para o restaurante conferir antes de repetir.
        if (result.failure == DataFailure.uncertain) unawaited(load());
        return _visible(result.message, saveError);
      }
      _upsert(product);
      return null;
    } catch (_) {
      if (_disposed) return null;
      return saveError;
    } finally {
      _saving = false;
      _notify();
    }
  }

  /// `null` quando o soft-delete confirmou. O produto permanece na lista, esgotado.
  Future<String?> deactivate(String id) async {
    if (_disposed || _saving || id.isEmpty) return deactivateError;
    _saving = true;
    _notify();
    try {
      final result = await _repository.deactivate(id);
      if (_disposed) return null;
      if (!result.removed) return _visible(result.message, deactivateError);
      _markUnavailable(id);
      return null;
    } catch (_) {
      if (_disposed) return null;
      return deactivateError;
    } finally {
      _saving = false;
      _notify();
    }
  }

  Object _draft({
    required String name,
    required String description,
    required String category,
    required String priceText,
    required String imageText,
    required String ingredientsText,
    required bool available,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || trimmedName.length > 120) return nameError;
    if (description.length > 2000) return descriptionError;
    final trimmedCategory = category.trim();
    if (trimmedCategory.isEmpty) return categoryError;
    final priceCents = tryParsePriceCents(priceText);
    if (priceCents == null) return priceError;
    final image = imageText.trim();
    final imageUrl = image.isEmpty ? null : image;
    final ingredients = [
      for (final part in ingredientsText.split('\n'))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    try {
      return ProductInput(
        name: trimmedName,
        description: description.trim(),
        category: trimmedCategory,
        priceCents: priceCents,
        imageUrl: imageUrl,
        available: available,
        ingredients: ingredients,
      );
    } on ArgumentError {
      if (imageUrl != null && Uri.tryParse(imageUrl)?.hasScheme != true) return imageError;
      return ingredientsError;
    }
  }

  void _upsert(Product product) {
    final next = [..._products];
    final index = next.indexWhere((item) => item.id == product.id);
    if (index < 0) {
      next.add(product);
    } else {
      next[index] = product;
    }
    _products = List.unmodifiable(next);
    _status = ProductCatalogStatus.ready;
    _errorMessage = null;
    _failure = null;
  }

  void _markUnavailable(String id) {
    _products = List.unmodifiable([
      for (final product in _products)
        if (product.id != id)
          product
        else
          Product(
            id: product.id,
            name: product.name,
            description: product.description,
            category: product.category,
            priceCents: product.priceCents,
            imageUrl: product.imageUrl,
            available: false,
            ingredients: product.ingredients,
          ),
    ]);
  }

  String _visible(String? message, String fallback) {
    if (message == null || message.isEmpty) return fallback;
    return message;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// `32,90`, `32.90` e `32` viram centavos. Vazio e texto fora desse formato voltam `null`.
int? tryParsePriceCents(String raw) {
  var text = raw.trim().replaceAll(r'$', '').replaceAll('R', '').replaceAll(' ', '');
  if (text.isEmpty || text.startsWith('-')) return null;

  final String reais;
  final String cents;
  if (text.contains(',')) {
    text = text.replaceAll('.', '');
    final parts = text.split(',');
    if (parts.length != 2 || !_digits(parts[0]) || !_cents(parts[1])) return null;
    reais = parts[0];
    cents = parts[1].padRight(2, '0');
  } else if (text.contains('.')) {
    final parts = text.split('.');
    if (parts.length != 2 || !_digits(parts[0]) || !_cents(parts[1])) return null;
    reais = parts[0];
    cents = parts[1].padRight(2, '0');
  } else if (_digits(text)) {
    reais = text;
    cents = '00';
  } else {
    return null;
  }

  final whole = int.tryParse(reais);
  final fraction = int.tryParse(cents);
  if (whole == null || fraction == null) return null;
  return whole * 100 + fraction;
}

/// Centavos do contrato no texto do formulário: `3290` vira `32,90`.
String formatPriceInput(int priceCents) {
  final whole = priceCents ~/ 100;
  final cents = (priceCents % 100).toString().padLeft(2, '0');
  return '$whole,$cents';
}

bool _digits(String value) => value.isNotEmpty && int.tryParse(value) != null;

bool _cents(String value) => value.isNotEmpty && value.length <= 2 && int.tryParse(value) != null;
