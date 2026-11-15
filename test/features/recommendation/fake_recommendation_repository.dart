import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_request.dart';

class FakeRecommendationRepository implements RecommendationRepository {
  FakeRecommendationRepository(this._recommend);

  final Future<RecommendationAttempt> Function(RecommendationRequest request) _recommend;
  int calls = 0;
  RecommendationRequest? lastRequest;

  @override
  Future<RecommendationAttempt> recommend(RecommendationRequest request) {
    calls += 1;
    lastRequest = request;
    return _recommend(request);
  }
}
