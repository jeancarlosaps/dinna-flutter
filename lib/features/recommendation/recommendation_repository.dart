import '../../core/domain/data_failure.dart';
import 'recommendation.dart';
import 'recommendation_request.dart';

/// Falha já separada do sucesso HTTP, inclusive do fallback.
enum RecommendationFailure {
  /// `400`. A API recusou o body.
  validation,

  /// Rede, tempo esgotado, `500` ou corpo fora do contrato.
  unavailable,
}

/// Resultado de uma tentativa de recomendação.
///
/// [recommendation] preenchida é sucesso HTTP, inclusive fallback e lista
/// vazia. Falha deixa a recomendação nula e traz o texto seguro da tela.
final class RecommendationAttempt {
  const RecommendationAttempt.ready(Recommendation this.recommendation)
    : failure = null,
      title = null,
      message = null;

  const RecommendationAttempt.failed(this.failure, {required this.title, required this.message})
    : recommendation = null;

  final Recommendation? recommendation;
  final RecommendationFailure? failure;
  final String? title;
  final String? message;
}

/// Fonte da recomendação. O ViewModel não vê HTTP.
abstract interface class RecommendationRepository {
  /// Título quando não houve `200` utilizável.
  static const failureTitle = 'Não foi possível pedir uma sugestão';

  /// Texto que acompanha [failureTitle]. Não fala de pedido registrado.
  static const failureMessage = 'O cardápio, o carrinho e o pedido continuam disponíveis.';

  Future<RecommendationAttempt> recommend(RecommendationRequest request);
}

/// Traduz [DataFailure] só para os dois desfechos desta rota.
RecommendationFailure recommendationFailureOf(DataFailure failure) {
  return failure == DataFailure.validation
      ? RecommendationFailure.validation
      : RecommendationFailure.unavailable;
}
