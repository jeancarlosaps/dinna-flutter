import 'package:dinna/features/home/api_status_repository.dart';

class FakeApiStatusRepository implements ApiStatusRepository {
  FakeApiStatusRepository(this._result);

  final Future<bool> Function() _result;

  @override
  Future<bool> isApiOnline() => _result();
}
