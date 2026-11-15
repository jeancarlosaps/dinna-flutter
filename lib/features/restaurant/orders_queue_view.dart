import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/dinna_layout.dart';
import '../../core/domain/order.dart';
import '../../core/domain/order_item.dart';
import '../../core/domain/order_status.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import 'order_format.dart';
import 'orders_queue_view_model.dart';
import 'panel_brand_bar.dart';
import 'restaurant_bottom_nav.dart';
import 'restaurant_rail.dart';

/// Fila de pedidos do restaurante, na rota `/restaurant`.
///
/// Cards compactos: mesa, status e itens. Avanço de status fica no detalhe.
class OrdersQueueView extends StatefulWidget {
  const OrdersQueueView({
    super.key,
    required this.createViewModel,
    this.routeObserver,
    this.onOrderSelected,
    this.onOpenProducts,
    this.buildOrderPane,
    this.onLeave,
    this.active = true,
  });

  final OrdersQueueViewModel Function() createViewModel;
  final RouteObserver<PageRoute<dynamic>>? routeObserver;

  /// Abre o detalhe. O valor devolvido, quando é um [Order], entra na fila
  /// antes do próximo refresh — um GET que falhe não descarta o status já confirmado.
  final FutureOr<Object?> Function(BuildContext context, Order order)? onOrderSelected;

  /// Abre o cadastro de produtos. Nulo esconde o atalho da fila.
  final void Function(BuildContext context)? onOpenProducts;

  /// Detalhe ao lado da fila quando a largura chega no tablet.
  ///
  /// [onChanged] devolve o pedido depois de um avanço de status.
  final Widget Function(BuildContext context, Order order, ValueChanged<Order> onChanged)?
  buildOrderPane;

  /// Toque na marca. No app, volta para a home.
  final void Function(BuildContext context)? onLeave;

  /// Falso quando a seção de produtos está na frente. A fila para de consultar.
  final bool active;

  @override
  State<OrdersQueueView> createState() => _OrdersQueueViewState();
}

class _OrdersQueueViewState extends State<OrdersQueueView> with WidgetsBindingObserver, RouteAware {
  late final OrdersQueueViewModel _viewModel = widget.createViewModel();
  OrderStatus? _statusFilter;
  String? _selectedOrderId;
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
  void didUpdateWidget(OrdersQueueView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncPolling();
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
    if (_routeIsCurrent && _appInForeground && widget.active) {
      _viewModel.resume();
    } else {
      _viewModel.pause();
    }
  }

  Future<void> _openOrder(Order order) async {
    final result = await widget.onOrderSelected!(context, order);
    if (!mounted || result is! Order) return;
    _viewModel.applyConfirmedUpdate(result);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = DinnaLayout.isTablet(constraints.maxWidth);
        final split = wide && widget.buildOrderPane != null;
        final showRail = wide && widget.onOpenProducts != null;
        return Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide && widget.onLeave != null) PanelBrandBar(onLeave: widget.onLeave!),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showRail)
                      RestaurantRail(
                        section: RestaurantSection.orders,
                        onProducts: () => widget.onOpenProducts!(context),
                        onLeave: widget.onLeave == null ? null : () => widget.onLeave!(context),
                      ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _viewModel,
                        builder: (context, _) {
                          final orders = _viewModel.orders;
                          final selected = !split
                              ? null
                              : orders.where((order) => order.id == _selectedOrderId).firstOrNull ??
                                    (orders.isEmpty ? null : orders.first);
                          final body = _QueueBody(
                            viewModel: _viewModel,
                            orders: _visibleOrders(),
                            showFilters: _viewModel.orders.isNotEmpty,
                            statusFilter: _statusFilter,
                            onStatusFilter: (status) => setState(() => _statusFilter = status),
                            onOrderSelected: widget.onOrderSelected == null
                                ? null
                                : (context, order) {
                                    if (split) {
                                      setState(() => _selectedOrderId = order.id);
                                      return;
                                    }
                                    unawaited(_openOrder(order));
                                  },
                            selectedOrderId: selected?.id,
                          );
                          if (!split) return body;
                          return _SplitQueue(list: body, pane: _detailsPane(selected));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: !wide && widget.onOpenProducts != null
              ? RestaurantBottomNav(
                  section: RestaurantSection.orders,
                  onProducts: () => widget.onOpenProducts!(context),
                )
              : null,
        );
      },
    );
  }

  List<Order> _visibleOrders() {
    final orders = _viewModel.orders;
    final filter = _statusFilter;
    if (filter == null) return orders;
    return [
      for (final order in orders)
        if (order.status == filter) order,
    ];
  }

  Widget _detailsPane(Order? selected) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: selected == null
          ? const Center(child: Text('Selecione um pedido'))
          : widget.buildOrderPane!(context, selected, _viewModel.applyConfirmedUpdate),
    );
  }
}

class _SplitQueue extends StatelessWidget {
  const _SplitQueue({required this.list, required this.pane});

  final Widget list;
  final Widget pane;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 400, child: list),
        Expanded(child: pane),
      ],
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({
    required this.viewModel,
    required this.onOrderSelected,
    required this.orders,
    this.showFilters = false,
    this.statusFilter,
    this.onStatusFilter,
    this.selectedOrderId,
  });

  final OrdersQueueViewModel viewModel;
  final void Function(BuildContext context, Order order)? onOrderSelected;
  final List<Order> orders;
  final bool showFilters;
  final OrderStatus? statusFilter;
  final ValueChanged<OrderStatus?>? onStatusFilter;
  final String? selectedOrderId;

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
      return _ScrollableFill(
        child: DinnaEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Não foi possível carregar',
          message: message,
          actionLabel: 'Tentar novamente',
          onAction: viewModel.retry,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.refreshError case final message?)
          _RefreshNotice(message: message, onRetry: viewModel.retry),
        if (viewModel.orders.isEmpty)
          Expanded(
            child: _ScrollableFill(
              child: Column(
                children: [
                  _QueueHeader(count: 0),
                  const DinnaEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Nenhum pedido na fila',
                    message: 'Quando um cliente enviar um pedido, ele aparece aqui.',
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                _QueueHeader(count: viewModel.orders.length),
                if (showFilters) ...[
                  const SizedBox(height: 8),
                  _StatusFilters(
                    orders: viewModel.orders,
                    selected: statusFilter,
                    onSelected: onStatusFilter,
                  ),
                ],
                const SizedBox(height: 12),
                if (orders.isEmpty)
                  const DinnaEmptyState(
                    icon: Icons.filter_alt_outlined,
                    title: 'Nenhum pedido neste filtro',
                    message: 'Escolha outro status ou volte para todos.',
                  )
                else
                  for (var index = 0; index < orders.length; index++) ...[
                    if (index > 0) const SizedBox(height: 8),
                    _OrderTile(
                      key: ValueKey(orders[index].id),
                      order: orders[index],
                      selected: orders[index].id == selectedOrderId,
                      onOpen: onOrderSelected == null
                          ? null
                          : () => onOrderSelected!(context, orders[index]),
                    ),
                  ],
              ],
            ),
          ),
      ],
    );
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({required this.orders, required this.selected, required this.onSelected});

  final List<Order> orders;
  final OrderStatus? selected;
  final ValueChanged<OrderStatus?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final chips = <(OrderStatus?, String)>[
      (null, 'Todos'),
      (OrderStatus.received, 'Recebidos'),
      (OrderStatus.preparing, 'Em preparo'),
      (OrderStatus.ready, 'Prontos'),
    ];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 40 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        primary: false,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (status, label) = chips[index];
          return ChoiceChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text('$label · ${_count(status)}'),
            selected: selected == status,
            onSelected: onSelected == null ? null : (_) => onSelected!(status),
          );
        },
      ),
    );
  }

  int _count(OrderStatus? status) {
    if (status == null) return orders.length;
    return orders.where((order) => order.status == status).length;
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

class _ScrollableFill extends StatelessWidget {
  const _ScrollableFill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
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
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pedidos', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            'Hoje · $label',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({super.key, required this.order, required this.onOpen, this.selected = false});

  final Order order;
  final VoidCallback? onOpen;
  final bool selected;

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
        side: BorderSide(
          color: selected ? scheme.primary : (ready ? scheme.secondary : scheme.outlineVariant),
          width: selected ? 1.5 : 1,
        ),
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
                label: _orderSemanticsLabel(
                  order: order,
                  time: time,
                  status: status,
                  canOpen: onOpen != null,
                ),
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Mesa ${order.table}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            _StatusPill(label: status, status: order.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          time,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (order.orderNumber != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            publicOrderLabel(order.orderNumber),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        for (var i = 0; i < order.items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 4),
                          _ItemRow(item: order.items[i]),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.status});

  final String label;
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = orderStatusColor(scheme, status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: orderStatusContainerColor(scheme, status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
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

String _orderSemanticsLabel({
  required Order order,
  required String time,
  required String status,
  required bool canOpen,
}) {
  final items = [
    for (final item in order.items) '${item.quantity}× ${orderItemDisplayName(item.name)}',
  ].join(', ');
  final number = order.orderNumber == null ? '' : ', ${publicOrderLabel(order.orderNumber)}';
  final summary = 'Mesa ${order.table}$number, $time, $status. $items';
  return canOpen ? '$summary. Ver detalhes' : summary;
}
