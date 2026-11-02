import 'package:flutter/foundation.dart';

import '../../core/domain/product.dart';
import 'product_repository.dart';

/// Estado do cardápio para a View.
enum MenuStatus { loading, ready, failed }

/// Cardápio do cliente: ViewModel → [ProductRepository.list].
///
/// Agrupa por categoria na ordem em que a API devolve e filtra pela
/// categoria escolhida. Categoria nula significa "Todos".
class MenuViewModel extends ChangeNotifier {
  MenuViewModel(this._repository);

  final ProductRepository _repository;

  static const fallbackErrorMessage = 'Não foi possível carregar o cardápio.';

  MenuStatus _status = MenuStatus.loading;
  List<Product> _products = const [];
  String? _errorMessage;
  String? _selectedCategory;
  bool _disposed = false;

  MenuStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get selectedCategory => _selectedCategory;

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

  Future<void> load() async {
    _status = MenuStatus.loading;
    _errorMessage = null;
    notifyListeners();

    ProductList result;
    try {
      result = await _repository.list();
    } catch (_) {
      result = const ProductList.unavailable(fallbackErrorMessage);
    }
    if (_disposed) return;

    final products = result.products;
    if (products == null) {
      _status = MenuStatus.failed;
      _errorMessage = result.message ?? fallbackErrorMessage;
    } else {
      _status = MenuStatus.ready;
      _products = products;
    }
    notifyListeners();
  }

  void selectCategory(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
