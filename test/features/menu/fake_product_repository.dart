import 'package:dinna/core/domain/product.dart';
import 'package:dinna/features/menu/product_repository.dart';

class FakeProductRepository implements ProductRepository {
  FakeProductRepository(
    this._list, {
    this.onFindById,
    this.onCreate,
    this.onUpdate,
    this.onDeactivate,
  });

  final Future<ProductList> Function() _list;
  final Future<ProductDetail> Function(String id)? onFindById;
  final Future<ProductSave> Function(ProductInput input)? onCreate;
  final Future<ProductSave> Function(String id, ProductInput input)? onUpdate;
  final Future<ProductSave> Function(String id)? onDeactivate;
  int calls = 0;
  int findCalls = 0;
  int createCalls = 0;
  int updateCalls = 0;
  int deactivateCalls = 0;
  ProductInput? lastInput;
  String? lastId;

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

  @override
  Future<ProductSave> create(ProductInput input) {
    createCalls++;
    lastInput = input;
    final create = onCreate;
    if (create == null) {
      throw UnimplementedError('create');
    }
    return create(input);
  }

  @override
  Future<ProductSave> update({required String id, required ProductInput input}) {
    updateCalls++;
    lastId = id;
    lastInput = input;
    final update = onUpdate;
    if (update == null) {
      throw UnimplementedError('update');
    }
    return update(id, input);
  }

  @override
  Future<ProductSave> deactivate(String id) {
    deactivateCalls++;
    lastId = id;
    final deactivate = onDeactivate;
    if (deactivate == null) {
      throw UnimplementedError('deactivate');
    }
    return deactivate(id);
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
