import 'package:flutter/foundation.dart';

import 'recommendation.dart';
import 'recommendation_preferences.dart';
import 'recommendation_repository.dart';
import 'recommendation_request.dart';

/// O que a tela de recomendação está mostrando.
enum RecommendationPhase {
  /// Formulário com as respostas atuais.
  editing,

  /// Há um POST em andamento. Outro toque não dispara outro envio.
  loading,

  /// `answered` + `suggestions`.
  suggestions,

  /// `unavailable` + `suggestions`. Sucesso com fallback, não é erro.
  fallback,

  /// `not_called` + `no_compatible_products`.
  noCompatibleProducts,

  /// `not_called` + `empty_catalog`.
  emptyCatalog,

  /// HTTP, transporte ou JSON fora dos quatro pares.
  failed,
}

/// Formulário "Me ajuda a escolher" e o resultado do POST.
///
/// As cinco escolhas não ganham default. Restrição marcada permanece no
/// pedido. Contradição desabilita o envio e não apaga o que a pessoa marcou.
class RecommendationViewModel extends ChangeNotifier {
  RecommendationViewModel(this._repository, {this.table, this.limit = 3});

  final RecommendationRepository _repository;
  final String? table;
  final int limit;

  static const fishAndSeafoodMessage = 'Peixe não combina com a restrição sem frutos do mar.';

  static const animalAndVeganMessage = 'A proteína escolhida não cabe numa restrição vegana.';

  MealBudget? _budget;
  MealHunger? _hunger;
  MealProtein? _protein;
  MealStyle? _style;
  MealTaste? _taste;
  List<DietaryRestriction> _restrictions = const [];

  RecommendationPhase _phase = RecommendationPhase.editing;
  List<RecommendationSuggestion> _suggestions = const [];
  String? _errorTitle;
  String? _errorMessage;
  RecommendationFailure? _failure;
  bool _inFlight = false;
  bool _disposed = false;
  int _generation = 0;

  MealBudget? get budget => _budget;
  MealHunger? get hunger => _hunger;
  MealProtein? get protein => _protein;
  MealStyle? get style => _style;
  MealTaste? get taste => _taste;
  List<DietaryRestriction> get restrictions => _restrictions;
  RecommendationPhase get phase => _phase;
  List<RecommendationSuggestion> get suggestions => _suggestions;
  String? get errorTitle => _errorTitle;
  String? get errorMessage => _errorMessage;
  RecommendationFailure? get failure => _failure;

  /// As cinco perguntas respondidas, sem contradição e sem POST em curso.
  bool get canSubmit => _answered && contradiction == null && !_inFlight;

  bool get _answered =>
      _budget != null && _hunger != null && _protein != null && _style != null && _taste != null;

  /// Mensagem visível enquanto a combinação é recusada. Nula se pode enviar
  /// ou se ainda falta alguma escolha única.
  String? get contradiction {
    final selectedProtein = _protein;
    if (selectedProtein == null) return null;
    final blocksSeafood = _restrictions.contains(DietaryRestriction.noSeafood);
    final blocksVegan = _restrictions.contains(DietaryRestriction.vegan);
    if (selectedProtein == MealProtein.fish && blocksSeafood) return fishAndSeafoodMessage;
    if (blocksVegan && selectedProtein != MealProtein.vegetarian) return animalAndVeganMessage;
    return null;
  }

  void selectBudget(MealBudget? value) => _select(() => _budget = value ?? _budget, value);

  void selectHunger(MealHunger? value) => _select(() => _hunger = value ?? _hunger, value);

  void selectProtein(MealProtein? value) => _select(() => _protein = value ?? _protein, value);

  void selectStyle(MealStyle? value) => _select(() => _style = value ?? _style, value);

  void selectTaste(MealTaste? value) => _select(() => _taste = value ?? _taste, value);

  void _select(void Function() apply, Object? value) {
    if (value == null || _disposed) return;
    apply();
    notifyListeners();
  }

  /// Marca ou desmarca uma restrição. As outras escolhas ficam onde estão.
  void setRestriction(DietaryRestriction restriction, {required bool selected}) {
    if (_disposed) return;
    final next = {..._restrictions};
    if (selected) {
      next.add(restriction);
    } else {
      next.remove(restriction);
    }
    _restrictions = List.unmodifiable([
      for (final item in DietaryRestriction.values)
        if (next.contains(item)) item,
    ]);
    notifyListeners();
  }

  /// Envia o body atual. Ignora toque repetido enquanto o POST não volta.
  ///
  /// Uma resposta de geração anterior, ou que chega depois do [dispose],
  /// não altera o estado.
  Future<void> submit() async {
    if (_disposed || _inFlight || !_answered || contradiction != null) return;

    final generation = ++_generation;
    _inFlight = true;
    _phase = RecommendationPhase.loading;
    _suggestions = const [];
    _errorTitle = null;
    _errorMessage = null;
    _failure = null;
    notifyListeners();

    RecommendationAttempt attempt;
    try {
      final request = RecommendationRequest(
        table: table,
        preferences: RecommendationPreferences(
          budget: _budget!,
          hunger: _hunger!,
          protein: _protein!,
          style: _style!,
          taste: _taste!,
          restrictions: _restrictions,
        ),
        limit: limit,
      );
      attempt = await _repository.recommend(request);
    } catch (_) {
      attempt = const RecommendationAttempt.failed(
        RecommendationFailure.unavailable,
        title: RecommendationRepository.failureTitle,
        message: RecommendationRepository.failureMessage,
      );
    }
    if (_disposed || generation != _generation) return;

    _inFlight = false;
    _apply(attempt);
    notifyListeners();
  }

  /// Volta ao formulário com as mesmas respostas e invalida o POST em curso.
  void returnToEditing() {
    if (_disposed) return;
    if (_phase == RecommendationPhase.editing && !_inFlight) return;
    _generation++;
    _inFlight = false;
    _phase = RecommendationPhase.editing;
    _suggestions = const [];
    _errorTitle = null;
    _errorMessage = null;
    _failure = null;
    notifyListeners();
  }

  void _apply(RecommendationAttempt attempt) {
    final recommendation = attempt.recommendation;
    if (recommendation == null) {
      _phase = RecommendationPhase.failed;
      _failure = attempt.failure ?? RecommendationFailure.unavailable;
      _errorTitle = attempt.title ?? RecommendationRepository.failureTitle;
      _errorMessage = attempt.message ?? RecommendationRepository.failureMessage;
      _suggestions = const [];
      return;
    }

    _failure = null;
    _errorTitle = null;
    _errorMessage = null;
    _suggestions = recommendation.products;
    _phase = switch ((recommendation.provider, recommendation.outcome)) {
      (RecommendationProvider.unavailable, RecommendationOutcome.suggestions) =>
        RecommendationPhase.fallback,
      (RecommendationProvider.answered, RecommendationOutcome.suggestions) =>
        RecommendationPhase.suggestions,
      (RecommendationProvider.notCalled, RecommendationOutcome.noCompatibleProducts) =>
        RecommendationPhase.noCompatibleProducts,
      (RecommendationProvider.notCalled, RecommendationOutcome.emptyCatalog) =>
        RecommendationPhase.emptyCatalog,
      _ => RecommendationPhase.failed,
    };
    if (_phase == RecommendationPhase.failed) {
      _failure = RecommendationFailure.unavailable;
      _errorTitle = RecommendationRepository.failureTitle;
      _errorMessage = RecommendationRepository.failureMessage;
      _suggestions = const [];
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
