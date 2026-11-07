import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/domain/order.dart';
import '../../../shared/widgets/dinna_banner.dart';
import '../../../shared/widgets/dinna_empty_state.dart';
import '../../restaurant/order_format.dart';
import '../order/order_submission_view_model.dart';
import 'cart_session.dart';
import 'cart_view_model.dart';

/// Revisão do carrinho, na rota `/cart`.
///
/// O [CartViewModel] nasce e morre com o State. O [OrderSubmissionViewModel]
/// vem da sessão: esta tela observa e não descarta, para um retorno a `/cart`
/// não começar outro POST. Em produção, a lista vem da [CartSession] e cada
/// alteração espera o SQLite; fluxos em memória ainda podem ser injetados.
/// O primeiro envio usa a mesa da navegação e as linhas confirmadas atuais.
/// Falha confirmada oferece nova tentativa. Resultado incerto só reenvia a
/// mesma tentativa depois de uma confirmação. [onOpenMenu] abre o cardápio no
/// estado vazio; a rota fica no router. [onOrderConfirmed] abre a confirmação
/// com o [Order] já gravado. Sem esse callback a tela continua no carrinho.
class CartView extends StatefulWidget {
  const CartView({
    super.key,
    required this.createViewModel,
    required this.submission,
    required this.onOpenMenu,
    this.cartSession,
    this.onOrderConfirmed,
    this.table,
  });

  final CartViewModel Function() createViewModel;
  final OrderSubmissionViewModel submission;
  final void Function(BuildContext context) onOpenMenu;
  final CartSession? cartSession;

  /// Abre `/order` com o pedido persistido. A rota fica no router.
  final Future<void> Function(BuildContext context, Order order)? onOrderConfirmed;

  /// Mesa recebida na navegação. Ausente até a tela da mesa entregar o valor.
  final String? table;

  @override
  State<CartView> createState() => _CartViewState();
}

class _CartViewState extends State<CartView> {
  CartViewModel? _viewModel;
  String? _presentedIntentId;
  var _confirmationFrame = false;
  var _confirmationOpen = false;

  OrderSubmissionViewModel get _submission => widget.submission;

  @override
  void initState() {
    super.initState();
    final session = widget.cartSession;
    if (session == null || session.isReady) {
      _initializeViewModel();
    } else {
      session.addListener(_onCartSession);
    }
    _submission.addListener(_onSubmission);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleAutomaticConfirmation();
    });
  }

  @override
  void dispose() {
    _submission.removeListener(_onSubmission);
    widget.cartSession?.removeListener(_onCartSession);
    _viewModel?.dispose();
    super.dispose();
  }

  void _onCartSession() {
    final session = widget.cartSession;
    if (!mounted || session == null || !session.isReady || _viewModel != null) return;
    setState(_initializeViewModel);
  }

  void _initializeViewModel() {
    _viewModel = widget.createViewModel();
    unawaited(_viewModel!.resolveProducts());
  }

  Future<void> _retryRestore(CartSession session) async {
    try {
      await session.restore();
    } catch (_) {
      // A sessão mantém o erro e a tela continua distinguindo falha de lista vazia.
    }
  }

  void _onSubmission() {
    _scheduleAutomaticConfirmation();
  }

  /// A rota do carrinho ainda está no topo e pode receber outra rota.
  ///
  /// Durante o retorno, o [State] continua [State.mounted] enquanto a
  /// transição reversa não termina. [ModalRoute.isCurrent] é que diz se um
  /// push cairia sobre esta tela. A intenção gravada não depende desta decisão.
  bool _cartRouteCanPresent() {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive || !route.isCurrent) return false;
    final animation = route.animation;
    return animation == null || animation.status != AnimationStatus.reverse;
  }

  /// Abre a confirmação uma vez por intenção, depois que o sucesso ficou gravado.
  ///
  /// A notificação do 201 pode acontecer com o envio ainda travado. A decisão
  /// espera o próximo frame e só segue se o carrinho continuar sendo a rota
  /// atual. [OrderSubmissionViewModel.canViewPersistedConfirmation] exige o
  /// arquivo. Resultado incerto, bloqueio e 201 sem arquivo não entram.
  /// Reconstrução e repetição da mesma intenção também não.
  void _scheduleAutomaticConfirmation() {
    if (!mounted || widget.onOrderConfirmed == null || _confirmationFrame || _confirmationOpen) {
      return;
    }
    if (!_cartRouteCanPresent() || !_submission.canViewPersistedConfirmation) return;
    final intentId = _submission.intentId;
    final order = _submission.order;
    if (intentId == null || order == null || _presentedIntentId == intentId) return;
    _confirmationFrame = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confirmationFrame = false;
      if (!mounted || !_cartRouteCanPresent()) return;
      unawaited(_openConfirmation(intentId, automatic: true));
    });
  }

  Future<void> _openConfirmation(String intentId, {required bool automatic}) async {
    if (!mounted || _confirmationOpen || !_cartRouteCanPresent()) return;
    if (!_submission.canViewPersistedConfirmation) return;
    final order = _submission.order;
    final open = widget.onOrderConfirmed;
    if (order == null || open == null || _submission.intentId != intentId) return;
    if (automatic && _presentedIntentId == intentId) return;
    _confirmationOpen = true;
    _presentedIntentId = intentId;
    try {
      await open(context, order);
    } finally {
      _confirmationOpen = false;
    }
  }

  void _viewConfirmation() {
    final intentId = _submission.intentId;
    if (intentId == null) return;
    unawaited(_openConfirmation(intentId, automatic: false));
  }

  Future<void> _submit() async {
    final viewModel = _viewModel;
    if (!_submission.canRequestSubmit ||
        viewModel == null ||
        viewModel.isMutating ||
        viewModel.items.isEmpty) {
      return;
    }
    await _submission.submit(table: widget.table ?? '', items: viewModel.items);
    _scheduleAutomaticConfirmation();
  }

  Future<void> _resume(String intentId) async {
    await _submission.resume(intentId);
    _scheduleAutomaticConfirmation();
  }

  Future<void> _beginAnother() => _submission.beginAnotherOrder();

  @override
  Widget build(BuildContext context) {
    final session = widget.cartSession;
    if (session != null && _viewModel == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Seu carrinho')),
        body: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            if (session.isReady) return const SizedBox.shrink();
            final hasError = session.restoreError != null;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!hasError || session.isRestoring)
                      const CircularProgressIndicator()
                    else ...[
                      const Icon(Icons.storage_rounded, size: 36),
                      const SizedBox(height: 12),
                      const Text(
                        'Não foi possível carregar seu carrinho. Tente novamente.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => unawaited(_retryRestore(session)),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    final viewModel = _viewModel!;
    return Scaffold(
      appBar: AppBar(title: const Text('Seu carrinho')),
      body: ListenableBuilder(
        listenable: Listenable.merge([viewModel, _submission]),
        builder: (context, _) {
          final hasRows = viewModel.rows.isNotEmpty;
          final submission = _SubmissionSection(
            submission: _submission,
            onSubmit: _submit,
            onResume: _resume,
            onBeginAnother: _beginAnother,
            onViewConfirmation: widget.onOrderConfirmed == null ? null : _viewConfirmation,
            allowSend: hasRows && !viewModel.isMutating,
          );
          if (!hasRows && _submission.status == OrderSubmissionStatus.idle) {
            return _EmptyCart(onOpenMenu: () => widget.onOpenMenu(context));
          }
          if (!hasRows) {
            return _EmptyCart(onOpenMenu: () => widget.onOpenMenu(context), notice: submission);
          }
          return _CartBody(viewModel: viewModel, submission: submission);
        },
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onOpenMenu, this.notice});

  final VoidCallback onOpenMenu;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final notice = this.notice;
        final empty = DinnaEmptyState(
          icon: Icons.shopping_cart_outlined,
          title: 'Seu carrinho está vazio',
          message: 'Escolha os pratos no cardápio e eles aparecem aqui para você revisar antes de enviar.',
          actionLabel: 'Ver cardápio',
          onAction: onOpenMenu,
          centered: notice == null,
        );
        if (notice == null) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: empty,
            ),
          );
        }
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: notice),
                empty,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.viewModel, required this.submission});

  final CartViewModel viewModel;
  final Widget submission;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 720 ? 720.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, height: constraints.maxHeight, child: _content(context)),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final rows = viewModel.rows;
    final lookupMessage = viewModel.productLookupMessage;
    final cartWriteError = viewModel.cartWriteErrorMessage;
    final total = viewModel.estimatedTotalCents;
    final unavailable = rows.any(
      (row) => !row.isAvailable || row.name == CartViewModel.missingProductName,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(_countLabel(rows.length), style: theme.textTheme.bodyMedium),
        if (lookupMessage != null) ...[
          const SizedBox(height: 12),
          DinnaBanner(
            tone: DinnaBannerTone.warning,
            title: 'Preços indisponíveis',
            message: lookupMessage,
          ),
        ],
        if (cartWriteError != null) ...[
          const SizedBox(height: 12),
          DinnaBanner(
            tone: DinnaBannerTone.error,
            title: 'Carrinho não atualizado',
            message: cartWriteError,
          ),
        ],
        if (unavailable) ...[
          const SizedBox(height: 12),
          const DinnaBanner(
            tone: DinnaBannerTone.warning,
            title: 'Revise os itens do carrinho',
            message: 'Há produto indisponível ou ausente no cardápio. Remova-o ou confirme a disponibilidade antes de enviar.',
          ),
        ],
        if (viewModel.isResolvingProducts) ...[
          const SizedBox(height: 12),
          const _ResolvingPrices(),
        ],
        if (viewModel.isMutating) ...[const SizedBox(height: 12), const _SavingCart()],
        const SizedBox(height: 12),
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _LineCard(
            row: rows[index],
            onDecrease: viewModel.isMutating ? null : () => unawaited(viewModel.decrease(index)),
            onIncrease: viewModel.isMutating ? null : () => unawaited(viewModel.increase(index)),
            onRemove: viewModel.isMutating ? null : () => unawaited(viewModel.removeAt(index)),
          ),
        ],
        if (total != null) ...[const SizedBox(height: 16), _EstimatedTotal(totalCents: total)],
        const SizedBox(height: 16),
        submission,
      ],
    );
  }
}

class _SubmissionSection extends StatelessWidget {
  const _SubmissionSection({
    required this.submission,
    required this.onSubmit,
    required this.onResume,
    required this.onBeginAnother,
    required this.onViewConfirmation,
    required this.allowSend,
  });

  final OrderSubmissionViewModel submission;
  final VoidCallback onSubmit;
  final void Function(String intentId) onResume;
  final VoidCallback onBeginAnother;
  final VoidCallback? onViewConfirmation;
  final bool allowSend;

  @override
  Widget build(BuildContext context) {
    final message = submission.errorMessage;
    final failed = submission.isDefiniteFailure;
    final sent = submission.status == OrderSubmissionStatus.succeeded;
    final received = submission.canViewPersistedConfirmation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (submission.isSubmitting) const _SendingNotice(),
        if (failed && message != null)
          DinnaBanner(tone: DinnaBannerTone.error, title: 'Pedido não enviado', message: message),
        if (submission.outcomeUncertain && message != null)
          DinnaBanner(
            tone: DinnaBannerTone.warning,
            title: 'Envio sem confirmação',
            message: '$message\n\n${OrderSubmissionViewModel.verifyBeforeRetryGuidance}',
          ),
        if (submission.resendBlocked && message != null)
          DinnaBanner(tone: DinnaBannerTone.warning, title: 'Confira o pedido', message: message),
        if (received)
          const DinnaBanner(
            tone: DinnaBannerTone.info,
            title: 'Pedido enviado',
            message: 'O restaurante recebeu o pedido.',
          ),
        if (received && onViewConfirmation != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onViewConfirmation,
            child: const Text('Ver confirmação', textAlign: TextAlign.center),
          ),
        ],
        if (sent && submission.canBeginAnotherOrder) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onBeginAnother,
            child: const Text('Fazer outro pedido', textAlign: TextAlign.center),
          ),
        ],
        if (allowSend && submission.canRequestSubmit) ...[
          if (failed) const SizedBox(height: 12),
          FilledButton(
            onPressed: onSubmit,
            child: Text(failed ? 'Tentar novamente' : 'Enviar pedido', textAlign: TextAlign.center),
          ),
        ],
        if (submission.canResumeSameIntent) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final intentId = submission.intentId;
              if (intentId == null) return;
              _confirmResume(context, intentId);
            },
            child: const Text('Reenviar o mesmo pedido', textAlign: TextAlign.center),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmResume(BuildContext context, String intentId) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reenviar o mesmo pedido?'),
        content: const Text(
          'O restaurante pode já ter recebido este pedido. O reenvio repete a mesma tentativa e não cria outro pedido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reenviar'),
          ),
        ],
      ),
    );
    if (accepted == true) onResume(intentId);
  }
}

class _SendingNotice extends StatelessWidget {
  const _SendingNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Enviando pedido',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ResolvingPrices extends StatelessWidget {
  const _ResolvingPrices();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Carregando nomes e preços',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _SavingCart extends StatelessWidget {
  const _SavingCart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Salvando carrinho',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.row,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final CartRow row;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = row.note;
    final lineTotal = row.lineTotalCents;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(row.name, style: theme.textTheme.titleMedium),
            ),
            if (note != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  note,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton(
                  tooltip: 'Diminuir quantidade',
                  onPressed: row.quantity <= 1 ? null : onDecrease,
                  icon: const Icon(Icons.remove),
                ),
                Text('${row.quantity}', style: theme.textTheme.titleMedium),
                IconButton(
                  tooltip: 'Aumentar quantidade',
                  onPressed: onIncrease,
                  icon: const Icon(Icons.add),
                ),
                if (lineTotal != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        formatOrderTotal(lineTotal),
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onRemove, child: const Text('Remover')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstimatedTotal extends StatelessWidget {
  const _EstimatedTotal({required this.totalCents});

  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = formatOrderTotal(totalCents);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Total estimado, $amount',
      child: Row(
        children: [
          Expanded(child: Text('Total estimado', style: theme.textTheme.titleMedium)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(amount, textAlign: TextAlign.end, style: theme.textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}

String _countLabel(int count) => count == 1 ? '1 item' : '$count itens';
