import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/widgets/dinna_banner.dart';
import '../../../shared/widgets/dinna_empty_state.dart';
import '../../restaurant/order_format.dart';
import '../order/order_submission_view_model.dart';
import 'cart_view_model.dart';

/// Revisão do carrinho, na rota `/cart`.
///
/// O [CartViewModel] e o [OrderSubmissionViewModel] nascem e morrem com o
/// State. A lista vem de [CartLines] e cada alteração volta por `replace`.
/// O envio usa a mesa que a navegação entregou e as linhas atuais. Falha
/// confirmada oferece nova tentativa. Resultado incerto não reenvia.
/// [onOpenMenu] abre o cardápio no estado vazio; a rota fica no router.
class CartView extends StatefulWidget {
  const CartView({
    super.key,
    required this.createViewModel,
    required this.createSubmission,
    required this.onOpenMenu,
    this.table,
  });

  final CartViewModel Function() createViewModel;
  final OrderSubmissionViewModel Function() createSubmission;
  final void Function(BuildContext context) onOpenMenu;

  /// Mesa recebida na navegação. Ausente até a tela da mesa entregar o valor.
  final String? table;

  @override
  State<CartView> createState() => _CartViewState();
}

class _CartViewState extends State<CartView> {
  late final CartViewModel _viewModel;
  late final OrderSubmissionViewModel _submission;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.createViewModel();
    _submission = widget.createSubmission();
    unawaited(_viewModel.resolveProducts());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _submit() {
    if (!_submission.canRequestSubmit) return Future<void>.value();
    return _submission.submit(table: widget.table ?? '', items: _viewModel.items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seu carrinho')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_viewModel, _submission]),
        builder: (context, _) {
          if (_viewModel.rows.isEmpty) {
            return _EmptyCart(onOpenMenu: () => widget.onOpenMenu(context));
          }
          return _CartBody(viewModel: _viewModel, submission: _submission, onSubmit: _submit);
        },
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onOpenMenu});

  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: DinnaEmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Seu carrinho está vazio',
              message: 'Escolha os pratos no cardápio e eles aparecem aqui para você revisar antes de enviar.',
              actionLabel: 'Ver cardápio',
              onAction: onOpenMenu,
            ),
          ),
        );
      },
    );
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.viewModel, required this.submission, required this.onSubmit});

  final CartViewModel viewModel;
  final OrderSubmissionViewModel submission;
  final VoidCallback onSubmit;

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
    final total = viewModel.estimatedTotalCents;
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
        if (viewModel.isResolvingProducts) ...[
          const SizedBox(height: 12),
          const _ResolvingPrices(),
        ],
        const SizedBox(height: 12),
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _LineCard(
            row: rows[index],
            onDecrease: () => viewModel.decrease(index),
            onIncrease: () => viewModel.increase(index),
            onRemove: () => viewModel.removeAt(index),
          ),
        ],
        if (total != null) ...[const SizedBox(height: 16), _EstimatedTotal(totalCents: total)],
        const SizedBox(height: 16),
        _SubmissionSection(submission: submission, onSubmit: onSubmit),
      ],
    );
  }
}

class _SubmissionSection extends StatelessWidget {
  const _SubmissionSection({required this.submission, required this.onSubmit});

  final OrderSubmissionViewModel submission;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final message = submission.errorMessage;
    final failed = submission.isDefiniteFailure;
    final sent = submission.status == OrderSubmissionStatus.succeeded;
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
        if (sent)
          const DinnaBanner(
            tone: DinnaBannerTone.info,
            title: 'Pedido enviado',
            message: 'O restaurante recebeu o pedido.',
          ),
        if (submission.canRequestSubmit) ...[
          if (failed) const SizedBox(height: 12),
          FilledButton(
            onPressed: onSubmit,
            child: Text(failed ? 'Tentar novamente' : 'Enviar pedido', textAlign: TextAlign.center),
          ),
        ],
      ],
    );
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

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.row,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final CartRow row;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

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
