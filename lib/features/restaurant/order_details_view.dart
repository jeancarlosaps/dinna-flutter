import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/router/app_route_args.dart';
import '../../core/domain/order.dart';
import '../../core/domain/order_status.dart';
import '../../shared/widgets/dinna_banner.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import 'order_details_view_model.dart';
import 'order_format.dart';

/// Detalhe de um pedido da fila, na rota `/restaurant/order`.
///
/// Lê [RestaurantOrderArgs] da rota. Sem o pedido já carregado, explica a
/// ausência e não consulta `GET /orders`. O avanço de status fica fixo no rodapé.
class OrderDetailsView extends StatefulWidget {
  const OrderDetailsView({
    super.key,
    required this.createViewModel,
    this.order,
    this.embedded = false,
    this.onChanged,
  });

  final OrderDetailsViewModel Function(Order order) createViewModel;

  /// Pedido já em mãos. No tablet o painel passa o pedido da fila.
  /// Na rota, o pedido continua vindo dos argumentos.
  final Order? order;

  /// Dentro da fila larga: não empurra outra rota e não intercepta o voltar.
  final bool embedded;

  /// A fila aplica o pedido quando o status muda no painel.
  final ValueChanged<Order>? onChanged;

  @override
  State<OrderDetailsView> createState() => _OrderDetailsViewState();
}

class _OrderDetailsViewState extends State<OrderDetailsView> {
  OrderDetailsViewModel? _viewModel;
  Order? _published;
  bool _adopting = false;
  var _closing = false;

  void _requestClose() {
    if (_closing) return;
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(_viewModel?.order);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureViewModel();
  }

  @override
  void didUpdateWidget(OrderDetailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.order;
    final current = _viewModel;
    if (next == null || current == null) return;
    if (next.id != current.order.id) {
      current.removeListener(_publish);
      current.dispose();
      _viewModel = null;
      _ensureViewModel();
      return;
    }
    // A fila já tem este pedido: não devolver o snapshot durante o build dela.
    _adopting = true;
    current.adopt(next);
    _adopting = false;
    _published = current.order;
  }

  void _ensureViewModel() {
    if (_viewModel != null) return;
    final order = widget.order ?? _orderFromRoute();
    if (order == null) return;
    final viewModel = widget.createViewModel(order);
    viewModel.addListener(_publish);
    _viewModel = viewModel;
    _published = viewModel.order;
    unawaited(viewModel.resolveProducts());
  }

  /// Só devolve à fila o pedido que mudou no painel, como o avanço confirmado.
  /// Falha do PATCH ou consulta de produtos não reenviam um snapshot antigo.
  void _publish() {
    if (!widget.embedded || _adopting) return;
    final order = _viewModel?.order;
    if (order == null || order == _published) return;
    _published = order;
    widget.onChanged?.call(order);
  }

  Order? _orderFromRoute() {
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is! RestaurantOrderArgs) return null;
    if (arguments.id.value != arguments.order.id) return null;
    return arguments.order;
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_publish);
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel;
    if (widget.embedded) {
      return Scaffold(
        body: viewModel == null
            ? const _MissingOrder()
            : ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) => _DetailsScaffold(viewModel: viewModel),
              ),
      );
    }
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _closing) return;
        _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: viewModel == null
            ? const _MissingOrder()
            : ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) => _DetailsScaffold(viewModel: viewModel),
              ),
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

class _DetailsScaffold extends StatelessWidget {
  const _DetailsScaffold({required this.viewModel});

  final OrderDetailsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final action = orderAdvanceActionLabel(viewModel.status);
    final ready = viewModel.status == OrderStatus.ready;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(child: _DetailsBody(viewModel: viewModel)),
        if (action != null)
          Material(
            elevation: 6,
            color: scheme.surfaceContainerLowest,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: ready ? scheme.secondary : null,
                        foregroundColor: ready ? scheme.onSecondary : null,
                      ),
                      onPressed: viewModel.isUpdating ? null : viewModel.advanceStatus,
                      child: viewModel.isUpdating
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : Text(action),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
    final scheme = theme.colorScheme;
    final items = viewModel.items;
    final lookupMessage = viewModel.productLookupMessage;
    final actionError = viewModel.actionError;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SummaryCard(viewModel: viewModel),
        if (actionError != null) ...[
          const SizedBox(height: 10),
          DinnaBanner(
            tone: DinnaBannerTone.error,
            title: 'Não foi possível avançar',
            message: actionError,
          ),
        ],
        if (lookupMessage != null) ...[
          const SizedBox(height: 10),
          DinnaBanner(
            tone: DinnaBannerTone.warning,
            title: 'Nomes indisponíveis',
            message: lookupMessage,
          ),
        ],
        const SizedBox(height: 16),
        Text('Itens', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (viewModel.isResolvingProducts) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                'Carregando nomes…',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _ItemCard(item: items[index]),
        ],
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 12),
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
    final scheme = theme.colorScheme;
    final time = formatOrderTimestamp(viewModel.createdAt);
    final status = orderStatusLabel(viewModel.status);
    final number = viewModel.orderNumber == null
        ? ''
        : ', ${publicOrderLabel(viewModel.orderNumber)}';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Mesa ${viewModel.table}, $time, $status$number',
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mesa ${viewModel.table}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (viewModel.orderNumber != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        publicOrderLabel(viewModel.orderNumber),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      time,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                status,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: orderStatusColor(scheme, viewModel.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final OrderDetailItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = item.note;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.quantity}×',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.name,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (item.lineTotalCents != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    formatOrderTotal(item.lineTotalCents!),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
        Expanded(
          child: Text(
            'Total',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          formatOrderTotal(totalCents),
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
