import 'package:flutter/foundation.dart';

import '../../core/domain/data_failure.dart';
import '../client/cart/cart_session.dart';
import '../menu/product_repository.dart';
import 'recommendation.dart';
import 'recommendation_catalog.dart';
import 'recommendation_preferences.dart';
import 'recommendation_repository.dart';
import 'recommendation_request.dart';

/// O que a tela de recomendação está mostrando.
enum RecommendationPhase {
  /// Formulário com as respostas atuais.
  editing,

  /// Há um POST em andamento. Outro toque não dispara outro envio.
  loading,

  /// `answered` + `suggestions`, com ao menos um prato disponível no cardápio.
  suggestions,

  /// `unavailable` + `suggestions`, com ao menos um prato disponível.
  /// Sucesso com fallback, não é erro.
  fallback,

  /// `not_called` + `no_compatible_products`.
  noCompatibleProducts,

  /// `not_called` + `empty_catalog`.
  emptyCatalog,

  /// A IA devolveu ids, mas nenhum existe e está disponível.
  noAvailableProducts,

  /// A consulta ao cardápio falhou depois de uma recomendação com sugestões.
  catalogFailed,

  /// HTTP, transporte ou JSON fora dos quatro pares.
  failed,
}

/// Inclusão de uma sugestão no carrinho já aberto.
sealed class RecommendationCartAddition {
  const RecommendationCartAddition();
}

/// A sessão confirmou a nova linha.
final class RecommendationCartAdded extends RecommendationCartAddition {
  const RecommendationCartAdded(this.productName);

  final String productName;
}

/// O toque não gravou. [message] é o que a tela pode mostrar.
final class RecommendationCartRejected extends RecommendationCartAddition {
  const RecommendationCartRejected(this.message);

  final String message;
}

/// Toque repetido ou resposta que chegou depois do encerramento da tela.
final class RecommendationCartIgnored extends RecommendationCartAddition {
  const RecommendationCartIgnored();
}

/// Formulário "Me ajuda a escolher" e o resultado do POST.
///
/// As cinco escolhas não ganham default. Restrição marcada permanece no
/// pedido. Contradição desabilita o envio e não apaga o que a pessoa marcou.
class RecommendationViewModel extends ChangeNotifier {
  RecommendationViewModel(
    this._repository, {
    required ProductRepository products,
    this.cartSession,
    this.table,
    this.limit = 3,
  }) : _products = products,
       _catalog = RecommendationCatalog(products);

  final RecommendationRepository _repository;
  final ProductRepository _products;
  final RecommendationCatalog _catalog;

  /// Carrinho já restaurado da sessão. Nulo não cria outro carrinho.
  final CartSession? cartSession;
  final String? table;
  final int limit;

  static const fishAndSeafoodMessage = 'Peixe não combina com a restrição sem frutos do mar.';

  static const animalAndVeganMessage = 'A proteína escolhida não cabe numa restrição vegana.';

  static const catalogFailureTitle = 'Não foi possível carregar os pratos sugeridos';

  static const catalogFailureMessage = 'O cardápio, o carrinho e o pedido continuam disponíveis.';

  static const unavailableProductMessage = 'Este prato não está disponível para pedir agora.';

  static const addFailureMessage = 'Não foi possível adicionar o produto. Tente novamente.';

  MealBudget? _budget;
  MealHunger? _hunger;
  MealProtein? _protein;
  MealStyle? _style;
  MealTaste? _taste;
  List<DietaryRestriction> _restrictions = const [];

  RecommendationPhase _phase = RecommendationPhase.editing;
  List<RecommendedProduct> _recommendedProducts = const [];
  bool _usedFallback = false;
  String? _errorTitle;
  String? _errorMessage;
  RecommendationFailure? _failure;
  bool _inFlight = false;
  bool _disposed = false;
  int _generation = 0;
  final Set<String> _addingProductIds = <String>{};

  MealBudget? get budget => _budget;
  MealHunger? get hunger => _hunger;
  MealProtein? get protein => _protein;
  MealStyle? get style => _style;
  MealTaste? get taste => _taste;
  List<DietaryRestriction> get restrictions => _restrictions;
  RecommendationPhase get phase => _phase;

  /// Pratos reais, na ordem das sugestões. Vazio fora de [RecommendationPhase.suggestions]
  /// e [RecommendationPhase.fallback].
  List<RecommendedProduct> get recommendedProducts => _recommendedProducts;

  /// Verdadeiro só quando há card e a lista veio do fallback.
  bool get usedFallback => _usedFallback;

  String? get errorTitle => _errorTitle;
  String? get errorMessage => _errorMessage;
  RecommendationFailure? get failure => _failure;

  /// As cinco perguntas respondidas, sem contradição e sem POST em curso.
  bool get canSubmit => _answered && contradiction == null && !_inFlight;

  /// A gravação deste prato ainda não foi confirmada pela sessão.
  bool isAdding(String productId) => _addingProductIds.contains(productId);

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
    _recommendedProducts = const [];
    _usedFallback = false;
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

    final recommendation = attempt.recommendation;
    if (recommendation == null || recommendation.outcome != RecommendationOutcome.suggestions) {
      _inFlight = false;
      _apply(attempt);
      notifyListeners();
      return;
    }

    final lookup = await _catalog.lookup(recommendation.products);
    if (_disposed || generation != _generation) return;

    _inFlight = false;
    _failure = null;
    final resolved = lookup.products;
    if (resolved == null) {
      _phase = RecommendationPhase.catalogFailed;
      _recommendedProducts = const [];
      _usedFallback = false;
      _errorTitle = catalogFailureTitle;
      _errorMessage = catalogFailureMessage;
      notifyListeners();
      return;
    }

    _errorTitle = null;
    _errorMessage = null;
    if (resolved.isEmpty) {
      _phase = RecommendationPhase.noAvailableProducts;
      _recommendedProducts = const [];
      _usedFallback = false;
      notifyListeners();
      return;
    }

    _recommendedProducts = resolved;
    _usedFallback = recommendation.usedFallback;
    _phase = _usedFallback ? RecommendationPhase.fallback : RecommendationPhase.suggestions;
    notifyListeners();
  }

  /// Inclui um prato que está na lista atual, com quantidade 1.
  ///
  /// Um segundo toque no mesmo prato espera a sessão confirmar a gravação.
  /// Produto ausente ou indisponível não chega ao repositório. Depois do
  /// [dispose], a resposta pendente não altera este ViewModel.
  Future<RecommendationCartAddition> addRecommended(String productId) async {
    if (_disposed || _addingProductIds.contains(productId)) {
      return const RecommendationCartIgnored();
    }

    final suggested = _suggested(productId);
    if (suggested == null || !suggested.product.available) {
      return const RecommendationCartRejected(unavailableProductMessage);
    }

    final session = cartSession;
    if (session == null || !session.isReady) {
      return const RecommendationCartRejected(addFailureMessage);
    }

    _addingProductIds.add(productId);
    notifyListeners();
    try {
      final detail = await _products.findById(productId);
      if (_disposed) return const RecommendationCartIgnored();
      final product = detail.product;
      if (product == null) {
        if (detail.failure == DataFailure.notFound) {
          return const RecommendationCartRejected(unavailableProductMessage);
        }
        return const RecommendationCartRejected(addFailureMessage);
      }
      if (product.id != productId || !product.available) {
        return const RecommendationCartRejected(unavailableProductMessage);
      }

      await session.addLine(productId: productId, quantity: 1);
      if (_disposed) return const RecommendationCartIgnored();
      return RecommendationCartAdded(product.name);
    } catch (_) {
      if (_disposed) return const RecommendationCartIgnored();
      return const RecommendationCartRejected(addFailureMessage);
    } finally {
      _addingProductIds.remove(productId);
      if (!_disposed) notifyListeners();
    }
  }

  RecommendedProduct? _suggested(String productId) {
    for (final suggestion in _recommendedProducts) {
      if (suggestion.product.id == productId) return suggestion;
    }
    return null;
  }

  /// Volta ao formulário com as mesmas respostas e invalida o POST em curso.
  void returnToEditing() {
    if (_disposed) return;
    if (_phase == RecommendationPhase.editing && !_inFlight) return;
    _generation++;
    _inFlight = false;
    _phase = RecommendationPhase.editing;
    _recommendedProducts = const [];
    _usedFallback = false;
    _errorTitle = null;
    _errorMessage = null;
    _failure = null;
    notifyListeners();
  }

  /// Outcomes sem sugestão e falha da recomendação. Sugestão com card passa
  /// pelo catálogo em [submit].
  void _apply(RecommendationAttempt attempt) {
    final recommendation = attempt.recommendation;
    _recommendedProducts = const [];
    _usedFallback = false;
    if (recommendation == null) {
      _phase = RecommendationPhase.failed;
      _failure = attempt.failure ?? RecommendationFailure.unavailable;
      _errorTitle = attempt.title ?? RecommendationRepository.failureTitle;
      _errorMessage = attempt.message ?? RecommendationRepository.failureMessage;
      return;
    }

    switch (recommendation.outcome) {
      case RecommendationOutcome.suggestions:
        _phase = RecommendationPhase.failed;
        _failure = RecommendationFailure.unavailable;
        _errorTitle = RecommendationRepository.failureTitle;
        _errorMessage = RecommendationRepository.failureMessage;
      case RecommendationOutcome.noCompatibleProducts:
        _failure = null;
        _errorTitle = null;
        _errorMessage = null;
        _phase = RecommendationPhase.noCompatibleProducts;
      case RecommendationOutcome.emptyCatalog:
        _failure = null;
        _errorTitle = null;
        _errorMessage = null;
        _phase = RecommendationPhase.emptyCatalog;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
