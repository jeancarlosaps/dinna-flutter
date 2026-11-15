import 'package:flutter/material.dart';

import '../../../core/domain/order_status.dart';
import '../../../shared/widgets/dinna_banner.dart';
import '../../../shared/widgets/dinna_empty_state.dart';
import '../../restaurant/order_format.dart';
import 'order_tracking_view_model.dart';

/// Status do pedido para o cliente, atualizado sozinho.
///
/// O [OrderTrackingViewModel] nasce e morre com o State. As consultas param
/// com o app em segundo plano ou com outra tela por cima e voltam, na hora,
/// quando a tela aparece de novo.
class OrderStatusTracker extends StatefulWidget {
  const OrderStatusTracker({super.key, required this.createViewModel, this.routeObserver});

  final OrderTrackingViewModel Function() createViewModel;

  /// A mesma instância do `MaterialApp`. Sem ela, a tela coberta continua
  /// consultando.
  final RouteObserver<PageRoute<dynamic>>? routeObserver;

  /// Aviso quando uma atualização falha e o status mostrado pode estar velho.
  static const refreshFailureMessage =
      'Sem conexão no momento. O status pode estar desatualizado; tentaremos de novo.';

  @override
  State<OrderStatusTracker> createState() => _OrderStatusTrackerState();
}

class _OrderStatusTrackerState extends State<OrderStatusTracker>
    with WidgetsBindingObserver, RouteAware {
  late final OrderTrackingViewModel _viewModel;
  PageRoute<dynamic>? _route;
  bool _routeIsCurrent = true;
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.createViewModel();
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
  void dispose() {
    widget.routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final order = _viewModel.order;
        if (_viewModel.notFound) {
          return const DinnaEmptyState(
            icon: Icons.search_off,
            title: 'Pedido não encontrado',
            message:
                'O restaurante não encontrou este pedido. Fale com a equipe se ele já foi feito.',
            centered: false,
          );
        }
        if (order != null) {
          return _StatusSteps(status: order.status, refreshFailed: _viewModel.refreshError != null);
        }
        final error = _viewModel.errorMessage;
        if (error != null) {
          return DinnaEmptyState(
            icon: Icons.wifi_off,
            title: 'Não foi possível consultar o pedido',
            message: error,
            actionLabel: 'Tentar de novo',
            onAction: _viewModel.isFetching ? null : _viewModel.retry,
            centered: false,
          );
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Consultando o pedido…', textAlign: TextAlign.center),
            ],
          ),
        );
      },
    );
  }
}

/// Frase do status atual para quem está na mesa.
String _statusMessage(OrderStatus status) => switch (status) {
  OrderStatus.received => 'O restaurante recebeu seu pedido.',
  OrderStatus.preparing => 'Seu pedido está sendo preparado.',
  OrderStatus.ready => 'Seu pedido está pronto e já vai para a mesa.',
  OrderStatus.finished => 'Pedido finalizado. Bom apetite!',
};

/// Os quatro passos do pedido, com o atual em destaque.
class _StatusSteps extends StatelessWidget {
  const _StatusSteps({required this.status, required this.refreshFailed});

  final OrderStatus status;
  final bool refreshFailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = OrderStatus.values.indexOf(status);
    final finished = status == OrderStatus.finished;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Uma única frase para o leitor de tela, anunciada quando muda.
        Semantics(
          liveRegion: true,
          label: 'Status do pedido: ${orderStatusLabel(status)}. ${_statusMessage(status)}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(_statusMessage(status), style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              for (final (index, step) in OrderStatus.values.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        index < current || (finished && index == current)
                            ? Icons.check_circle
                            : index == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: index <= current ? colors.primary : colors.outlineVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          orderStatusLabel(step),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: index == current ? FontWeight.w700 : null,
                            color: index <= current ? colors.onSurface : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (refreshFailed) ...[
          const DinnaBanner(
            tone: DinnaBannerTone.warning,
            message: OrderStatusTracker.refreshFailureMessage,
          ),
          const SizedBox(height: 12),
        ],
        if (!finished)
          Text(
            'O status atualiza sozinho.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
      ],
    );
  }
}
