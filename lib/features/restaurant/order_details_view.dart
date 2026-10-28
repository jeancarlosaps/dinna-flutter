import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/router/app_route_args.dart';
import '../../core/domain/order.dart';
import '../../shared/widgets/dinna_banner.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import 'order_details_view_model.dart';
import 'order_format.dart';

/// Detalhe de um pedido da fila, na rota `/restaurant/order`.
///
/// Lê [RestaurantOrderArgs] da rota. Sem o pedido já carregado, explica a
/// ausência e não consulta `GET /orders`. O [OrderDetailsViewModel] nasce e
/// morre com o State.
class OrderDetailsView extends StatefulWidget {
  const OrderDetailsView({super.key, required this.createViewModel});

  final OrderDetailsViewModel Function(Order order) createViewModel;

  @override
  State<OrderDetailsView> createState() => _OrderDetailsViewState();
}

class _OrderDetailsViewState extends State<OrderDetailsView> {
  OrderDetailsViewModel? _viewModel;
  var _resolvedArguments = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedArguments) return;
    _resolvedArguments = true;
    final order = _orderFromRoute();
    if (order == null) return;
    final viewModel = widget.createViewModel(order);
    _viewModel = viewModel;
    unawaited(viewModel.resolveProducts());
  }

  Order? _orderFromRoute() {
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is! RestaurantOrderArgs) return null;
    if (arguments.id.value != arguments.order.id) return null;
    return arguments.order;
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel;
    return Scaffold(
      appBar: AppBar(title: const Text('Pedido')),
      body: viewModel == null
          ? const _MissingOrder()
          : ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) => _DetailsBody(viewModel: viewModel),
            ),
    );
  }
}

class _MissingOrder extends StatelessWidget {
  const _MissingOrder();

  @override
  Widget build(BuildContext context) {
    return const DinnaEmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'Pedido indisponível',
      message: 'Abra o pedido pela fila para ver a mesa, os itens e o horário.',
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.viewModel});

  final OrderDetailsViewModel viewModel;

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
    final items = viewModel.items;
    final lookupMessage = viewModel.productLookupMessage;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SummaryCard(viewModel: viewModel),
        if (lookupMessage != null) ...[
          const SizedBox(height: 12),
          DinnaBanner(
            tone: DinnaBannerTone.warning,
            title: 'Nomes indisponíveis',
            message: lookupMessage,
          ),
        ],
        const SizedBox(height: 20),
        Text('Itens', style: theme.textTheme.titleMedium),
        if (viewModel.isResolvingProducts) ...[const SizedBox(height: 12), const _ResolvingNames()],
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _ItemCard(item: items[index]),
        ],
        const SizedBox(height: 16),
        _TotalRow(totalCents: viewModel.totalCents),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.viewModel});

  final OrderDetailsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = formatOrderTimestamp(viewModel.createdAt);
    final status = orderStatusLabel(viewModel.status);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Mesa ${viewModel.table}, $time, $status',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mesa ${viewModel.table}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    time,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: orderStatusColor(theme.colorScheme, viewModel.status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResolvingNames extends StatelessWidget {
  const _ResolvingNames();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Carregando nomes dos produtos',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final OrderDetailItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = item.note;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item.quantity}×', style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                Expanded(child: Text(item.name, style: theme.textTheme.bodyLarge)),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(
                note,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.totalCents});

  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text('Total', style: theme.textTheme.titleMedium)),
        Text(formatOrderTotal(totalCents), style: theme.textTheme.titleMedium),
      ],
    );
  }
}
