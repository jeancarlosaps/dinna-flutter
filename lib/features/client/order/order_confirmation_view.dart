import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/router/app_route_args.dart';
import '../../../core/domain/order.dart';
import '../../../core/domain/order_item.dart';
import '../../../shared/widgets/dinna_empty_state.dart';
import '../../restaurant/order_format.dart';

/// Confirmação do pedido já aceito pela API, na rota `/order`.
///
/// Lê [OrderConfirmationArgs]. O [Order] é a fotografia gravada no envio:
/// mesa, itens, quantidades, total e horário vêm dele. [OrderItem] não traz
/// nome nem preço individual; a tela mostra o `productId` e não consulta o
/// cardápio. Sem o argumento certo, explica a ausência e não chama a API.
///
/// Não há ViewModel: o pedido é imutável e esta tela não envia, não retoma
/// e não observa o carrinho. [onTrack] abre o acompanhamento com o mesmo
/// [Order]. Um segundo toque enquanto a rota não voltou não empilha outra.
class OrderConfirmationView extends StatefulWidget {
  const OrderConfirmationView({super.key, required this.onTrack});

  final Future<void> Function(BuildContext context, Order order) onTrack;

  @override
  State<OrderConfirmationView> createState() => _OrderConfirmationViewState();
}

class _OrderConfirmationViewState extends State<OrderConfirmationView> {
  Order? _order;
  var _resolvedArguments = false;
  var _tracking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolvedArguments) return;
    _resolvedArguments = true;
    _order = _orderFromRoute();
  }

  Order? _orderFromRoute() {
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is! OrderConfirmationArgs) return null;
    return arguments.order;
  }

  Future<void> _track(Order order) async {
    if (_tracking) return;
    _tracking = true;
    try {
      await widget.onTrack(context, order);
    } finally {
      if (mounted) {
        setState(() => _tracking = false);
      } else {
        _tracking = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: const Text('Pedido recebido')),
      body: order == null
          ? const _MissingOrder()
          : _ConfirmationBody(order: order, onTrack: () => unawaited(_track(order))),
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
      message: 'Abra a confirmação depois que o restaurante receber o pedido.',
    );
  }
}

class _ConfirmationBody extends StatelessWidget {
  const _ConfirmationBody({required this.order, required this.onTrack});

  final Order order;
  final VoidCallback onTrack;

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
    final items = order.items;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const _ReceivedHeader(),
        const SizedBox(height: 16),
        _OrderCard(order: order),
        const SizedBox(height: 20),
        Text('Itens', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _ItemCard(item: items[index]),
        ],
        const SizedBox(height: 16),
        _TotalRow(totalCents: order.totalCents),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onTrack,
          child: const Text('Acompanhar pedido', textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

class _ReceivedHeader extends StatelessWidget {
  const _ReceivedHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Pedido recebido. O restaurante recebeu este pedido.',
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: colors.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.check_circle_outline, size: 32, color: colors.primary),
          ),
          const SizedBox(height: 16),
          Text('Pedido recebido', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'O restaurante recebeu este pedido.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = formatOrderTimestamp(order.createdAt);
    final status = orderStatusLabel(order.status);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Mesa ${order.table}, $time, $status, pedido ${order.id}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mesa ${order.table}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: orderStatusColor(theme.colorScheme, order.status),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                time,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text('Pedido', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(order.id, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = item.note;
    final units = item.quantity == 1 ? '1 unidade' : '${item.quantity} unidades';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$units do produto ${item.productId}${note == null ? '' : ', $note'}',
      child: Card(
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
                  Expanded(child: Text(item.productId, style: theme.textTheme.bodyLarge)),
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
    final amount = formatOrderTotal(totalCents);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Total, $amount',
      child: Row(
        children: [
          Expanded(child: Text('Total', style: theme.textTheme.titleMedium)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(amount, textAlign: TextAlign.end, style: theme.textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}
