import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/dinna_banner.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import '../menu/product_image.dart';
import '../restaurant/order_format.dart';
import 'recommendation_catalog.dart';
import 'recommendation_preferences.dart';
import 'recommendation_view_model.dart';

/// Aviso fixo do desenho. Não é um selo do prato.
const _allergyNotice = 'Tem alergia? Confirme os ingredientes com a equipe antes de pedir.';

const _fallbackTitle = 'A Dinna não respondeu agora';

const _fallbackMessage =
    'Seu pedido continua funcionando normalmente. Separei pratos do cardápio que batem com os seus filtros.';

const _noCompatibleTitle = 'Nenhum prato compatível';

const _noCompatibleMessage =
    'Não há, no cardápio disponível, um prato que respeite essas respostas sem completar informação que o cadastro não tem.';

const _emptyCatalogTitle = 'Cardápio vazio';

const _emptyCatalogMessage = 'O restaurante ainda não tem pratos disponíveis para sugerir.';

const _noAvailableTitle = 'Nenhum prato disponível';

const _noAvailableMessage = 'As sugestões recebidas não estão no cardápio disponível agora.';

const _failureTitle = 'Não foi possível pedir uma sugestão';

const _failureMessage = 'O cardápio, o carrinho e o pedido continuam disponíveis.';

/// Formulário e resultado de "Me ajuda a escolher".
///
/// O [RecommendationViewModel] nasce e morre com o State. Voltar no resultado
/// ou no carregamento retorna ao formulário. "Ver cardápio completo" chama
/// [onShowMenu], que desempilha esta rota. "Adicionar ao carrinho" grava na
/// sessão já aberta e não fecha esta tela. [onOpenCart] abre o carrinho
/// existente, com a mesma mesa.
class RecommendationView extends StatefulWidget {
  const RecommendationView({
    super.key,
    required this.createViewModel,
    required this.onShowMenu,
    this.onOpenCart,
  });

  final RecommendationViewModel Function() createViewModel;
  final void Function(BuildContext context) onShowMenu;
  final void Function(BuildContext context)? onOpenCart;

  @override
  State<RecommendationView> createState() => _RecommendationViewState();
}

class _RecommendationViewState extends State<RecommendationView> {
  late final RecommendationViewModel _viewModel;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  var _canOpenCart = false;
  var _openingCart = false;
  String? _cartError;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.createViewModel();
    _viewModel.addListener(_clearStaleCartError);
  }

  /// O erro da inclusão anterior não acompanha outra sugestão nem o formulário.
  void _clearStaleCartError() {
    if (!mounted || _cartError == null) return;
    final phase = _viewModel.phase;
    if (phase != RecommendationPhase.editing && phase != RecommendationPhase.loading) return;
    setState(() => _cartError = null);
  }

  /// A recomendação ainda é a rota de cima. Um push do carrinho deixa o State
  /// montado, mas o aviso e a navegação não podem sair desta rota.
  bool _recommendationIsCurrent() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive || !route.isCurrent) return false;
    final animation = route.animation;
    return animation == null || animation.status != AnimationStatus.reverse;
  }

  Future<void> _addRecommended(RecommendedProduct suggestion) async {
    if (mounted && _cartError != null) setState(() => _cartError = null);
    final result = await _viewModel.addRecommended(suggestion.product.id);
    if (!mounted) return;
    switch (result) {
      case RecommendationCartAdded(:final productName):
        setState(() {
          _canOpenCart = true;
          _cartError = null;
        });
        _showCartFeedback('$productName adicionado ao carrinho.', openCart: true);
      case RecommendationCartRejected(:final message):
        setState(() => _cartError = message);
      case RecommendationCartIgnored():
        break;
    }
  }

  void _showCartFeedback(String message, {bool openCart = false}) {
    if (!_recommendationIsCurrent()) return;
    final messenger = _messengerKey.currentState;
    final open = widget.onOpenCart;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: openCart && open != null
            ? SnackBarAction(label: 'Ver carrinho', onPressed: _openCart)
            : null,
      ),
    );
  }

  void _openCart() {
    final open = widget.onOpenCart;
    if (!_recommendationIsCurrent() ||
        open == null ||
        _openingCart ||
        _viewModel.hasPendingAddition) {
      return;
    }
    _openingCart = true;
    _messengerKey.currentState?.hideCurrentSnackBar();
    open(context);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_clearStaleCartError);
    _messengerKey.currentState?.hideCurrentSnackBar();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_openingCart && _recommendationIsCurrent()) _openingCart = false;
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final editing = _viewModel.phase == RecommendationPhase.editing;
        return PopScope(
          canPop: editing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _viewModel.returnToEditing();
          },
          child: ScaffoldMessenger(
            key: _messengerKey,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Me ajuda a escolher'),
                actions: [
                  if (_canOpenCart && widget.onOpenCart != null && !editing)
                    TextButton(
                      onPressed: _viewModel.hasPendingAddition ? null : _openCart,
                      child: const Text('Ver carrinho'),
                    ),
                ],
                leading: BackButton(
                  onPressed: () {
                    if (editing) {
                      Navigator.of(context).maybePop();
                    } else {
                      _viewModel.returnToEditing();
                    }
                  },
                ),
              ),
              body: SafeArea(
                child: switch (_viewModel.phase) {
                  RecommendationPhase.editing => _PreferenceForm(viewModel: _viewModel),
                  RecommendationPhase.loading => const _LoadingRecommendation(),
                  RecommendationPhase.suggestions => _SuggestionResult(
                    viewModel: _viewModel,
                    onShowMenu: () => widget.onShowMenu(context),
                    onAdd: (suggestion) => unawaited(_addRecommended(suggestion)),
                    cartError: _cartError,
                  ),
                  RecommendationPhase.fallback => _SuggestionResult(
                    viewModel: _viewModel,
                    onShowMenu: () => widget.onShowMenu(context),
                    onAdd: (suggestion) => unawaited(_addRecommended(suggestion)),
                    cartError: _cartError,
                    fallback: true,
                  ),
                  RecommendationPhase.noCompatibleProducts => _OutcomeMessage(
                    icon: Icons.search_off,
                    title: _noCompatibleTitle,
                    message: _noCompatibleMessage,
                    onShowMenu: () => widget.onShowMenu(context),
                    showAllergy: true,
                  ),
                  RecommendationPhase.emptyCatalog => _OutcomeMessage(
                    icon: Icons.restaurant_menu,
                    title: _emptyCatalogTitle,
                    message: _emptyCatalogMessage,
                    onShowMenu: () => widget.onShowMenu(context),
                  ),
                  RecommendationPhase.noAvailableProducts => _OutcomeMessage(
                    icon: Icons.search_off,
                    title: _noAvailableTitle,
                    message: _noAvailableMessage,
                    onShowMenu: () => widget.onShowMenu(context),
                    showAllergy: true,
                  ),
                  RecommendationPhase.catalogFailed => _OutcomeMessage(
                    icon: Icons.cloud_off,
                    title: _viewModel.errorTitle ?? RecommendationViewModel.catalogFailureTitle,
                    message:
                        _viewModel.errorMessage ?? RecommendationViewModel.catalogFailureMessage,
                    onShowMenu: () => widget.onShowMenu(context),
                    actionLabel: 'Tentar de novo',
                    onAction: () => unawaited(_viewModel.submit()),
                  ),
                  RecommendationPhase.failed => _OutcomeMessage(
                    icon: Icons.wifi_off,
                    title: _viewModel.errorTitle ?? _failureTitle,
                    message: _viewModel.errorMessage ?? _failureMessage,
                    onShowMenu: () => widget.onShowMenu(context),
                    actionLabel: 'Tentar de novo',
                    onAction: () => unawaited(_viewModel.submit()),
                  ),
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreferenceForm extends StatelessWidget {
  const _PreferenceForm({required this.viewModel});

  final RecommendationViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final contradiction = viewModel.contradiction;
    final colors = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const DinnaBanner(tone: DinnaBannerTone.info, message: _allergyNotice),
        const SizedBox(height: 20),
        _SingleChoice<MealBudget>(
          title: 'Quanto pretende gastar?',
          groupValue: viewModel.budget,
          options: MealBudget.values,
          labelOf: (option) => option.label,
          onChanged: viewModel.selectBudget,
        ),
        _SingleChoice<MealHunger>(
          title: 'Qual é o tamanho da sua fome?',
          groupValue: viewModel.hunger,
          options: MealHunger.values,
          labelOf: (option) => option.label,
          onChanged: viewModel.selectHunger,
        ),
        _SingleChoice<MealProtein>(
          title: 'Qual proteína prefere?',
          groupValue: viewModel.protein,
          options: MealProtein.values,
          labelOf: (option) => option.label,
          onChanged: viewModel.selectProtein,
        ),
        _SingleChoice<MealStyle>(
          title: 'Que tipo de refeição deseja?',
          groupValue: viewModel.style,
          options: MealStyle.values,
          labelOf: (option) => option.label,
          onChanged: viewModel.selectStyle,
        ),
        _SingleChoice<MealTaste>(
          title: 'Prefere salgado ou doce?',
          groupValue: viewModel.taste,
          options: MealTaste.values,
          labelOf: (option) => option.label,
          onChanged: viewModel.selectTaste,
        ),
        Text('Possui alguma restrição alimentar?', style: Theme.of(context).textTheme.titleMedium),
        Text(
          'Opcional. Pode marcar várias.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        for (final restriction in DietaryRestriction.values)
          CheckboxListTile(
            value: viewModel.restrictions.contains(restriction),
            onChanged: (selected) =>
                viewModel.setRestriction(restriction, selected: selected ?? false),
            title: Text(restriction.label),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            minTileHeight: 48,
          ),
        if (contradiction != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              contradiction,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: viewModel.canSubmit ? () => unawaited(viewModel.submit()) : null,
          child: const Text('Me sugere um prato'),
        ),
      ],
    );
  }
}

class _SingleChoice<T> extends StatelessWidget {
  const _SingleChoice({
    required this.title,
    required this.groupValue,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final T? groupValue;
  final List<T> options;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          RadioGroup<T>(
            groupValue: groupValue,
            onChanged: onChanged,
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<T>(
                    value: option,
                    title: Text(labelOf(option)),
                    selected: option == groupValue,
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 48,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingRecommendation extends StatelessWidget {
  const _LoadingRecommendation();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 48),
        Center(child: CircularProgressIndicator(semanticsLabel: 'Preparando uma sugestão')),
        SizedBox(height: 16),
        Text('Preparando uma sugestão…', textAlign: TextAlign.center),
      ],
    );
  }
}

class _SuggestionResult extends StatelessWidget {
  const _SuggestionResult({
    required this.viewModel,
    required this.onShowMenu,
    required this.onAdd,
    this.cartError,
    this.fallback = false,
  });

  final RecommendationViewModel viewModel;
  final VoidCallback onShowMenu;
  final ValueChanged<RecommendedProduct> onAdd;
  final String? cartError;
  final bool fallback;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (fallback) ...[
          const DinnaBanner(
            tone: DinnaBannerTone.warning,
            title: _fallbackTitle,
            message: _fallbackMessage,
          ),
          const SizedBox(height: 12),
        ],
        const DinnaBanner(tone: DinnaBannerTone.info, message: _allergyNotice),
        if (cartError != null) ...[
          const SizedBox(height: 12),
          DinnaBanner(tone: DinnaBannerTone.error, message: cartError!),
        ],
        const SizedBox(height: 16),
        for (final suggestion in viewModel.recommendedProducts) ...[
          _RecommendationCard(
            suggestion: suggestion,
            isAdding: viewModel.isAdding(suggestion.product.id),
            onAdd: () => onAdd(suggestion),
          ),
          const SizedBox(height: 12),
        ],
        if (fallback) ...[
          const SizedBox(height: 4),
          FilledButton(
            onPressed: () => unawaited(viewModel.submit()),
            child: const Text('Tentar a Dinna de novo'),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton(onPressed: onShowMenu, child: const Text('Ver cardápio completo')),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.suggestion,
    required this.isAdding,
    required this.onAdd,
  });

  final RecommendedProduct suggestion;
  final bool isAdding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final product = suggestion.product;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 170, child: ProductImage(product: product)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  formatOrderTotal(product.priceCents),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(suggestion.reason, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: isAdding ? null : onAdd,
                  child: isAdding
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Adicionar ao carrinho', textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OutcomeMessage extends StatelessWidget {
  const _OutcomeMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onShowMenu,
    this.actionLabel,
    this.onAction,
    this.showAllergy = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onShowMenu;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showAllergy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        DinnaEmptyState(
          centered: false,
          icon: icon,
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
        if (showAllergy) ...[
          const DinnaBanner(tone: DinnaBannerTone.info, message: _allergyNotice),
          const SizedBox(height: 12),
        ],
        OutlinedButton(onPressed: onShowMenu, child: const Text('Ver cardápio completo')),
      ],
    );
  }
}
