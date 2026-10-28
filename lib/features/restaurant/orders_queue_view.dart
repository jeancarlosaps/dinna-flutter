import 'package:flutter/material.dart';

import '../../core/domain/order.dart';
import 'order_format.dart';
import 'orders_queue_view_model.dart';

/// Fila de pedidos do restaurante, na rota `/restaurant`.
///
/// O app não tinha um ciclo de vida de tela. Esta View junta o que o Flutter
/// já oferece: [WidgetsBindingObserver] para o app em segundo plano e
/// [RouteAware] para quando outra rota cobre a fila. Os dois sinais entram
/// em [OrdersQueueViewModel.pause] e [OrdersQueueViewModel.resume]. O
/// [RouteObserver] é o mesmo registrado no `MaterialApp`.
class OrdersQueueView extends StatefulWidget {
  const OrdersQueueView({
    super.key,
    required this.createViewModel,
    this.routeObserver,
    this.onOrderSelected,
  });

  /// O ViewModel nasce e morre com o State da tela.
  final OrdersQueueViewModel Function() createViewModel;

  /// Observa cobertura da rota. Sem ele, o polling segue o ciclo do app.
  final RouteObserver<PageRoute<dynamic>>? routeObserver;

  /// Abre o detalhe. A View não escolhe a rota.
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
          child: SizedBox(width: width, height: constraints.maxHeight, child: _content()),
        );
      },
    );
  }

  Widget _content() {
    if (!viewModel.hasLoaded) {
      final message = viewModel.errorMessage;
      if (viewModel.isLoading || message == null) {
        return const _LoadingState();
      }
      return _MessageState(message: message, onRetry: viewModel.retry);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.refreshError case final message?)
          _RefreshNotice(message: message, onRetry: viewModel.retry),
        if (viewModel.orders.isEmpty)
          const Expanded(child: _EmptyState())
        else ...[
          const _QueueHint(),
          Expanded(
            child: _OrdersList(orders: viewModel.orders, onOrderSelected: onOrderSelected),
          ),
        ],
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight > 48 ? minHeight - 48 : 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Nenhum pedido na fila',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Quando um cliente enviar um pedido, ele aparece aqui.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight > 48 ? minHeight - 48 : 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_outlined, size: 40, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(message, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: onRetry, child: const Text('Tentar novamente')),
              ],
            ),
          ),
        );
      },
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: TextStyle(color: scheme.onErrorContainer)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueHint extends StatelessWidget {
  const _QueueHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(
        'Mais antigos primeiro',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.orders, required this.onOrderSelected});

  final List<Order> orders;
  final void Function(BuildContext context, Order order)? onOrderSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = orders[index];
        return _OrderTile(key: ValueKey(order.id), order: order, onOrderSelected: onOrderSelected);
      },
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({super.key, required this.order, required this.onOrderSelected});

  final Order order;
  final void Function(BuildContext context, Order order)? onOrderSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = formatOrderTimestamp(order.createdAt);
    final status = orderStatusLabel(order.status);
    final open = onOrderSelected;

    return Semantics(
      container: true,
      button: open != null,
      excludeSemantics: true,
      label: open == null
          ? 'Mesa ${order.table}, $time, $status'
          : 'Mesa ${order.table}, $time, $status. Abrir detalhes',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open == null ? null : () => open(context, order),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                    color: orderStatusColor(theme.colorScheme, order.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
