import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import 'recommendation.dart';
import 'recommendation_repository.dart';
import 'recommendation_request.dart';

/// Repository concreto de `POST /ai/recommendation`.
///
/// Usa o [ApiClient] já existente. Falha de transporte do `postJson` chega com
/// o texto do envio de pedido; esta classe troca esse texto antes da tela.
class HttpRecommendationRepository implements RecommendationRepository {
  HttpRecommendationRepository(this._apiClient);

  final ApiClient _apiClient;

  static const path = '/ai/recommendation';

  @override
  Future<RecommendationAttempt> recommend(RecommendationRequest request) async {
    try {
      final body = await _apiClient.postJson(path, request.toJson());
      return RecommendationAttempt.ready(Recommendation.fromJson(body));
    } on ApiException catch (error) {
      return _failed(recommendationFailureOf(error.failure));
    } on FormatException {
      return _failed(RecommendationFailure.unavailable);
    }
  }

  RecommendationAttempt _failed(RecommendationFailure failure) {
    return RecommendationAttempt.failed(
      failure,
      title: RecommendationRepository.failureTitle,
      message: RecommendationRepository.failureMessage,
    );
  }
}
