import 'package:dinna/features/home/api_status_repository.dart';

class FakeApiStatusRepository implements ApiStatusRepository {
  FakeApiStatusRepository(this._result);

  final Future<ApiAvailability> Function() _result;

  @override
  Future<ApiAvailability> checkHealth() => _result();
}
