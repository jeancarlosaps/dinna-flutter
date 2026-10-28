import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'api_status_repository.dart';

/// Repository concreto do `GET /health`, usando o [ApiClient] como Service.
class HttpApiStatusRepository implements ApiStatusRepository {
  HttpApiStatusRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiAvailability> checkHealth() async {
    try {
      final body = await _apiClient.getJson('/health');
      return switch (body) {
        {'status': 'ok'} => const ApiAvailability.online(),
        _ => const ApiAvailability.offline('Resposta inesperada da API'),
      };
    } on ApiException catch (error) {
      return ApiAvailability.offline(error.message, failure: error.failure, detail: error.detail);
    }
  }
}
