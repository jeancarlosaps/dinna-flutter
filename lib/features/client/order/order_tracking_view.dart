import 'package:flutter/material.dart';

import '../../../app/router/app_route_args.dart';
import '../../../shared/widgets/dinna_empty_state.dart';

/// Identificação do pedido na rota `/order/tracking`.
///
/// Lê [AppRouteId]. Não consulta a API, não observa status e não cria outro
/// pedido. A atualização do andamento fica fora desta tela. Sem o id, explica
/// a ausência.
class OrderTrackingView extends StatelessWidget {
  const OrderTrackingView({super.key});

  @override
  Widget build(BuildContext context) {
    final id = _orderId(ModalRoute.of(context)?.settings.arguments);
    return Scaffold(
      appBar: AppBar(title: const Text('Acompanhamento')),
      body: id == null ? const _MissingTracking() : _KnownOrder(id: id),
    );
  }

  String? _orderId(Object? arguments) {
    if (arguments is! AppRouteId) return null;
    if (arguments.value.trim().isEmpty) return null;
    return arguments.value;
  }
}

class _MissingTracking extends StatelessWidget {
  const _MissingTracking();

  @override
  Widget build(BuildContext context) {
    return const DinnaEmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'Acompanhamento indisponível',
      message: 'Abra o acompanhamento pela confirmação do pedido.',
    );
  }
}

class _KnownOrder extends StatelessWidget {
  const _KnownOrder({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 720 ? 720.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text('Pedido', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(id, style: Theme.of(context).textTheme.titleMedium),
                const DinnaEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Status ao vivo indisponível',
                  message: 'Este aplicativo ainda não atualiza o andamento do pedido.',
                  centered: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
