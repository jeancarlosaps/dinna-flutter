import 'package:flutter/material.dart';

import '../../../app/router/app_route_args.dart';
import '../../../shared/widgets/dinna_empty_state.dart';
import '../../restaurant/order_format.dart';

/// Identificação do pedido na rota `/order/tracking`.
///
/// Lê [OrderTrackingArgs] ou, ainda, [AppRouteId]. Não consulta a API, não
/// observa status e não cria outro pedido. Mostra o número público quando ele
/// veio no argumento. Sem o número, explica o pedido de forma neutra e não
/// exibe o UUID. A atualização do andamento fica fora desta tela. Sem id,
/// explica a ausência.
class OrderTrackingView extends StatelessWidget {
  const OrderTrackingView({super.key});

  @override
  Widget build(BuildContext context) {
    final tracked = _trackedOrder(ModalRoute.of(context)?.settings.arguments);
    return Scaffold(
      appBar: AppBar(title: const Text('Acompanhamento')),
      body: tracked == null
          ? const _MissingTracking()
          : _KnownOrder(orderNumber: tracked.orderNumber),
    );
  }

  /// `null` quando a rota não identifica um pedido. O número público pode
  /// faltar num pedido válido.
  _TrackedOrder? _trackedOrder(Object? arguments) {
    if (arguments is OrderTrackingArgs) {
      if (arguments.id.value.trim().isEmpty) return null;
      final number = arguments.orderNumber;
      if (number != null && number < 1) return const _TrackedOrder(null);
      return _TrackedOrder(number);
    }
    if (arguments is AppRouteId) {
      if (arguments.value.trim().isEmpty) return null;
      return const _TrackedOrder(null);
    }
    return null;
  }
}

/// Pedido já identificado. [orderNumber] nulo não é uma rota inválida.
final class _TrackedOrder {
  const _TrackedOrder(this.orderNumber);

  final int? orderNumber;
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
  const _KnownOrder({required this.orderNumber});

  final int? orderNumber;

  @override
  Widget build(BuildContext context) {
    final label = publicOrderLabel(orderNumber);
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
                Text(label, style: Theme.of(context).textTheme.titleMedium),
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
