import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/product_repository.dart';

class FakeProductRepository implements ProductRepository {
  FakeProductRepository(this._list, {this.onFindById});

  final Future<ProductList> Function() _list;
  final Future<ProductDetail> Function(String id)? onFindById;
  int calls = 0;
  int findCalls = 0;

  @override
  Future<ProductList> list() {
    calls++;
    return _list();
  }

  @override
  Future<ProductDetail> findById(String id) {
    findCalls++;
    final find = onFindById;
    if (find == null) {
      throw UnimplementedError('findById');
    }
    return find(id);
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
