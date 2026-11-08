import 'package:flutter/foundation.dart';

import '../../core/domain/product.dart';
import 'product_repository.dart';

/// Estado do cardápio para a View.
enum MenuStatus { loading, ready, failed }

/// Cardápio do cliente: ViewModel → [ProductRepository.list].
///
/// Agrupa por categoria na ordem em que a API devolve e filtra pela
/// categoria escolhida. Categoria nula significa "Todos". A busca pelo nome
/// filtra o cardápio já carregado, sem nova chamada à API.
class MenuViewModel extends ChangeNotifier {
  MenuViewModel(this._repository);

  final ProductRepository _repository;

  static const fallbackErrorMessage = 'Não foi possível carregar o cardápio.';

  MenuStatus _status = MenuStatus.loading;
  List<Product> _products = const [];
  String? _errorMessage;
  String? _selectedCategory;
  String _query = '';
  bool _disposed = false;
  int _loadGeneration = 0;

  MenuStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get selectedCategory => _selectedCategory;

  /// Texto da busca como veio do campo.
  String get query => _query;

  /// Há busca ativa: o texto tem algo além de espaços.
  bool get isSearching => _normalize(_query).isNotEmpty;

  /// Cardápio carregado e sem nenhum produto.
  bool get isEmpty => _status == MenuStatus.ready && _products.isEmpty;

  /// Categorias sem repetir, na ordem em que aparecem.
  List<String> get categories => {for (final product in _products) product.category}.toList();

  /// Produtos da categoria escolhida, ou todos.
  List<Product> get visibleProducts {
    final category = _selectedCategory;
    if (category == null) return _products;
    return _products.where((product) => product.category == category).toList();
  }

  /// Produtos de uma categoria, na ordem da API.
  List<Product> productsIn(String category) =>
      _products.where((product) => product.category == category).toList();

  /// Uma passagem pela lista, na ordem da API. A tela reutiliza cada grupo na seção.
  Map<String, List<Product>> groupedProducts() {
    final grouped = <String, List<Product>>{};
    for (final product in _products) {
      grouped.putIfAbsent(product.category, () => []).add(product);
    }
    return grouped;
  }

  /// [groupedProducts] só com os produtos cujo nome contém a busca, sem
  /// diferenciar maiúsculas nem acentos. Categoria sem resultado fica de fora.
  /// Sem busca, devolve o cardápio inteiro.
  Map<String, List<Product>> groupedMatches() {
    final term = _normalize(_query);
    if (term.isEmpty) return groupedProducts();
    final grouped = <String, List<Product>>{};
    for (final product in _products) {
      if (!_normalize(product.name).contains(term)) continue;
      grouped.putIfAbsent(product.category, () => []).add(product);
    }
    return grouped;
  }

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    _status = MenuStatus.loading;
    _errorMessage = null;
    notifyListeners();

    ProductList result;
    try {
      result = await _repository.list();
    } catch (_) {
      result = const ProductList.unavailable(fallbackErrorMessage);
    }
    if (_disposed || generation != _loadGeneration) return;

    final products = result.products;
    if (products == null) {
      _status = MenuStatus.failed;
      _errorMessage = result.message ?? fallbackErrorMessage;
    } else {
      _status = MenuStatus.ready;
      _products = products;
      // Categoria que sumiu do cardápio novo volta para "Todos".
      if (!products.any((product) => product.category == _selectedCategory)) {
        _selectedCategory = null;
      }
    }
    notifyListeners();
  }

  void selectCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void search(String text) {
    if (text == _query) return;
    _query = text;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Minúsculas, sem acento e com um espaço entre as palavras. Remove também
/// os acentos digitados como caractere combinante.
String _normalize(String text) {
  final buffer = StringBuffer();
  for (final char in text.trim().toLowerCase().split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer
      .toString()
      .replaceAll(RegExp('[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}
