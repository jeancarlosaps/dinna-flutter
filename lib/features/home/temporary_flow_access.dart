import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';

/// Atalho temporário para as rotas já mapeadas.
///
/// Apague este arquivo e a chamada em `HomeView` antes da entrega final.
/// Não cria rotas: só chama [Navigator.pushNamed] com os nomes de [AppRoutes].
///
/// Mesa, fila e detalhe do pedido usam as telas reais. Cardápio e detalhe de
/// produto ainda não têm View e caem no placeholder da rota. O detalhe do
/// pedido abre pelo toque na fila, com o pedido de `GET /orders`, sem
/// `POST /orders`.
class TemporaryFlowAccess extends StatelessWidget {
  const TemporaryFlowAccess({super.key});

  static const _clientEntries = <_FlowDestination>[
    _FlowDestination(label: 'Mesa', route: AppRoutes.table),
    _FlowDestination(label: 'Cardápio', route: AppRoutes.menu, pending: true),
    _FlowDestination(label: 'Detalhe do produto', route: AppRoutes.product, pending: true),
  ];

  static const _restaurantEntries = <_FlowDestination>[
    _FlowDestination(label: 'Fila de pedidos', route: AppRoutes.restaurant),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Acesso temporário', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Remover antes da entrega.', style: muted),
            const SizedBox(height: 12),
            Text('Cliente', style: theme.textTheme.labelLarge),
            for (final entry in _clientEntries) _FlowButton(destination: entry),
            const SizedBox(height: 8),
            Text('Restaurante', style: theme.textTheme.labelLarge),
            for (final entry in _restaurantEntries) _FlowButton(destination: entry),
            Text('O detalhe do pedido abre ao tocar um item da fila.', style: muted),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FlowDestination {
  const _FlowDestination({required this.label, required this.route, this.pending = false});

  final String label;
  final String route;
  final bool pending;
}

class _FlowButton extends StatelessWidget {
  const _FlowButton({required this.destination});

  final _FlowDestination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextButton(
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(40),
        padding: EdgeInsets.zero,
      ),
      onPressed: () {
        Navigator.of(context).pushNamed(destination.route);
      },
      child: Row(
        children: [
          Expanded(child: Text(destination.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (destination.pending)
            Text(
              'pendente',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
