import 'package:flutter/material.dart';

import '../../core/domain/order.dart';
import '../../core/domain/order_item.dart';
import '../../core/domain/order_status.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import 'order_format.dart';
import 'orders_queue_view_model.dart';

/// Fila de pedidos do restaurante, na rota `/restaurant`.
///
/// Cards compactos: mesa, status e itens. Avanço de status fica no detalhe.
class OrdersQueueView extends StatefulWidget {
  const OrdersQueueView({
    super.key,
    required this.createViewModel,
    this.routeObserver,
    this.onOrderSelected,
  });

  final OrdersQueueViewModel Function() createViewModel;
  final RouteObserver<PageRoute<dynamic>>? routeObserver;
  final void Function(BuildContext context, Order order)? onOrderSelected;

  @override
  State<OrdersQueueView> createState() => _OrdersQueueViewState();
}

class _OrdersQueueViewState extends State<OrdersQueueView> with WidgetsBindingObserver, RouteAware {
  late final OrdersQueueViewModel _viewModel = widget.createViewModel();
  PageRoute<dynamic>? _route;
  bool _routeIsCurrent = true;
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = widget.routeObserver;
    final route = ModalRoute.of(context);
    if (observer == null || route is! PageRoute<dynamic> || route == _route) return;
    if (_route != null) observer.unsubscribe(this);
    _route = route;
    observer.subscribe(this, route);
  }

  @override
  void dispose() {
    widget.routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    _syncPolling();
  }

  @override
  void didPushNext() {
    _routeIsCurrent = false;
    _syncPolling();
  }

  @override
  void didPopNext() {
    _routeIsCurrent = true;
    _syncPolling();
  }

  void _syncPolling() {
    if (_routeIsCurrent && _appInForeground) {
      _viewModel.resume();
    } else {
      _viewModel.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fila de pedidos')),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) =>
            _QueueBody(viewModel: _viewModel, onOrderSelected: widget.onOrderSelected),
      ),
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.viewModel, required this.onOrderSelected});

  final OrdersQueueViewModel viewModel;
  final void Function(BuildContext context, Order order)? onOrderSelected;

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
    if (!viewModel.hasLoaded) {
      final message = viewModel.errorMessage;
      if (viewModel.isLoading || message == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return DinnaEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar',
        message: message,
        actionLabel: 'Tentar novamente',
        onAction: viewModel.retry,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.refreshError case final message?)
          _RefreshNotice(message: message, onRetry: viewModel.retry),
        if (viewModel.orders.isEmpty)
          const Expanded(
            child: DinnaEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Nenhum pedido na fila',
              message: 'Quando um cliente enviar um pedido, ele aparece aqui.',
            ),
          )
        else ...[
          _QueueHeader(count: viewModel.orders.length),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: viewModel.orders.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final order = viewModel.orders[index];
                return _OrderTile(
                  key: ValueKey(order.id),
                  order: order,
                  onOpen: onOrderSelected == null ? null : () => onOrderSelected!(context, order),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _RefreshNotice extends StatelessWidget {
  const _RefreshNotice({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count == 1 ? '1 pedido' : '$count pedidos';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            'Em preparo primeiro',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({super.key, required this.order, required this.onOpen});

  final Order order;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = formatOrderTimestamp(order.createdAt);
    final status = orderStatusLabel(order.status);
    final accent = orderStatusColor(scheme, order.status);
    final ready = order.status == OrderStatus.ready;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: ready ? scheme.secondary : scheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(color: accent, child: const SizedBox(width: 3)),
            Expanded(
              child: Semantics(
                container: true,
                button: onOpen != null,
                excludeSemantics: true,
                onTap: onOpen,
                label: onOpen == null
                    ? 'Mesa ${order.table}, $time, $status'
                    : 'Mesa ${order.table}, $time, $status. Ver detalhes',
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Mesa ${order.table}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              status,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              time,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            if (onOpen != null) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < order.items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 4),
                          _ItemRow(item: order.items[i]),
                        ],
                        if (onOpen != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Ver detalhes',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '${item.quantity}×',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            orderItemDisplayName(item.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
