import '../../core/network/api_client.dart';

class ApiStatusRepository {
  ApiStatusRepository(this._apiClient);

  final ApiClient _apiClient;

  /// `true` quando `GET /health` responde `{ "status": "ok" }`.
  Future<bool> isApiOnline() async {
    final body = await _apiClient.getJson('/health');
    return switch (body) {
      {'status': 'ok'} => true,
      _ => false,
    };
  }
}
