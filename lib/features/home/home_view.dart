import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/order.dart';
import '../client/order/last_order_session.dart';
import '../restaurant/order_format.dart';
import 'home_view_model.dart';
import 'temporary_flow_access.dart';

/// Tela inicial provisória da fundação (R0). As telas reais do cliente e do
/// restaurante são implementadas nas Stories correspondentes.
///
/// [TemporaryFlowAccess] é o atalho de desenvolvimento. Apague o widget e o
/// arquivo antes da entrega; a marca e o cartão da API ficam.
class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.createViewModel,
    this.lastOrderSession,
    this.onOpenLastOrder,
  });

  /// O ViewModel nasce e morre com o State da tela.
  final HomeViewModel Function() createViewModel;
  final LastOrderSession? lastOrderSession;
  final Future<void> Function(BuildContext context, Order order)? onOpenLastOrder;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late final HomeViewModel _viewModel = widget.createViewModel();
  var _openingLastOrder = false;

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'dinna',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.displayMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Pedido à mesa, do seu jeito.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (widget.lastOrderSession case final session?) ...[
                              const SizedBox(height: 24),
                              _LastOrderCard(
                                session: session,
                                onOpen: widget.onOpenLastOrder == null || _openingLastOrder
                                    ? null
                                    : (order) => _openLastOrder(context, order),
                              ),
                            ],
                            const SizedBox(height: 32),
                            const TemporaryFlowAccess(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => _ApiStatusCard(viewModel: _viewModel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLastOrder(BuildContext context, Order order) {
    if (_openingLastOrder || ModalRoute.of(context)?.isCurrent != true) return;
    final onOpenLastOrder = widget.onOpenLastOrder;
    if (onOpenLastOrder == null) return;

    setState(() => _openingLastOrder = true);
    unawaited(_waitForLastOrderRoute(context, order, onOpenLastOrder));
  }

  Future<void> _waitForLastOrderRoute(
    BuildContext context,
    Order order,
    Future<void> Function(BuildContext context, Order order) onOpenLastOrder,
  ) async {
    try {
      await onOpenLastOrder(context, order);
    } finally {
      if (mounted) setState(() => _openingLastOrder = false);
    }
  }
}

class _LastOrderCard extends StatelessWidget {
  const _LastOrderCard({required this.session, required this.onOpen});

  final LastOrderSession session;
  final ValueChanged<Order>? onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final order = session.order;
        final error = session.errorMessage;
        if (!session.isRestored && order == null) return const SizedBox.shrink();
        if (order == null && error == null) return const SizedBox.shrink();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Último pedido', style: Theme.of(context).textTheme.titleMedium),
                if (order != null) ...[
                  const SizedBox(height: 4),
                  Text('Mesa ${order.table} · ${publicOrderLabel(order.orderNumber)}'),
                  if (onOpen != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => onOpen!(order),
                      child: const Text('Ver último pedido'),
                    ),
                  ],
                ],
                if (error case final message?) ...[
                  const SizedBox(height: 8),
                  Text(message),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: session.isSaving || session.isLoading ? null : () => _retry(),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _retry() async {
    try {
      await session.retry();
    } on Object {
      // A sessão mantém o estado e a mensagem para a próxima tentativa.
    }
  }
}

class _ApiStatusCard extends StatelessWidget {
  const _ApiStatusCard({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, color) = switch (viewModel.status) {
      ApiStatus.unknown => ('API não verificada', colors.onSurfaceVariant),
      ApiStatus.checking => ('Verificando…', colors.onSurfaceVariant),
      ApiStatus.online => ('API online', colors.secondary),
      ApiStatus.offline => ('API indisponível', colors.error),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            if (viewModel.errorMessage case final message?) ...[
              const SizedBox(height: 4),
              Text(message, style: TextStyle(color: colors.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: viewModel.status == ApiStatus.checking ? null : viewModel.checkApi,
              child: const Text('Verificar conexão com a API'),
            ),
          ],
        ),
      ),
    );
  }
}
