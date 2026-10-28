import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/product_repository.dart';

class FakeProductRepository implements ProductRepository {
  FakeProductRepository(this._list);

  final Future<ProductList> Function() _list;
  int calls = 0;

  @override
  Future<ProductList> list() {
    calls++;
    return _list();
  }
}

Product sampleProduct({required String id, required String name, bool available = true}) {
  return Product(
    id: id,
    name: name,
    description: '',
    category: 'burgers',
    priceCents: 1000,
    imageUrl: null,
    available: available,
  );
}
