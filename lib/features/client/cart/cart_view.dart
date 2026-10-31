import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/widgets/dinna_banner.dart';
import '../../../shared/widgets/dinna_empty_state.dart';
import '../../restaurant/order_format.dart';
import 'cart_view_model.dart';

/// Revisão do carrinho, na rota `/cart`.
///
/// O [CartViewModel] nasce e morre com o State. A lista vem de [CartLines]
/// e cada alteração volta por `write`. [onOpenMenu] abre o cardápio no
/// estado vazio; a rota fica no router.
class CartView extends StatefulWidget {
  const CartView({super.key, required this.createViewModel, required this.onOpenMenu});

  final CartViewModel Function() createViewModel;
  final void Function(BuildContext context) onOpenMenu;

  @override
  State<CartView> createState() => _CartViewState();
}

class _CartViewState extends State<CartView> {
  late final CartViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.createViewModel();
    unawaited(_viewModel.resolveProducts());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seu carrinho')),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.rows.isEmpty) {
            return _EmptyCart(onOpenMenu: () => widget.onOpenMenu(context));
          }
          return _CartBody(viewModel: _viewModel);
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
    return DinnaEmptyState(
      icon: Icons.shopping_cart_outlined,
      title: 'Seu carrinho está vazio',
      message:
          'Escolha os pratos no cardápio e eles aparecem aqui para você revisar antes de enviar.',
      actionLabel: 'Ver cardápio',
      onAction: onOpenMenu,
    );
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.viewModel});

  final CartViewModel viewModel;

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
                const Spacer(),
                if (lineTotal != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(formatOrderTotal(lineTotal), style: theme.textTheme.titleMedium),
                  ),
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
          Text(amount, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

String _countLabel(int count) => count == 1 ? '1 item' : '$count itens';
