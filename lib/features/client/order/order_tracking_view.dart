import 'package:flutter/material.dart';

import '../../../app/router/app_route_args.dart';
import '../../../shared/widgets/dinna_empty_state.dart';
import '../../restaurant/order_format.dart';
import 'order_status_tracker.dart';
import 'order_tracking_view_model.dart';

/// Identificação do pedido na rota `/order/tracking`.
///
/// Lê [OrderTrackingArgs] ou, ainda, [AppRouteId]. Não cria outro pedido.
/// Mostra o número público quando ele veio no argumento. Sem o número, explica
/// o pedido de forma neutra e não exibe o UUID, que só segue para a consulta.
/// Com [createViewModel], o status é consultado e atualizado sozinho pelo
/// [OrderStatusTracker]. Sem id, explica a ausência.
class OrderTrackingView extends StatelessWidget {
  const OrderTrackingView({super.key, this.createViewModel, this.routeObserver});

  /// Cria o ViewModel do status para o id da rota. Nulo: a tela não consulta
  /// o andamento.
  final OrderTrackingViewModel Function(String orderId)? createViewModel;

  /// A mesma instância do `MaterialApp`. Pausa a consulta com outra tela por cima.
  final RouteObserver<PageRoute<dynamic>>? routeObserver;

  @override
  Widget build(BuildContext context) {
    final tracked = _trackedOrder(ModalRoute.of(context)?.settings.arguments);
    return Scaffold(
      appBar: AppBar(title: const Text('Acompanhamento')),
      body: tracked == null
          ? const _MissingTracking()
          : _KnownOrder(
              orderId: tracked.id,
              orderNumber: tracked.orderNumber,
              createViewModel: createViewModel,
              routeObserver: routeObserver,
            ),
    );
  }

  /// `null` quando a rota não identifica um pedido. O número público pode
  /// faltar num pedido válido.
  _TrackedOrder? _trackedOrder(Object? arguments) {
    if (arguments is OrderTrackingArgs) {
      final id = arguments.id.value;
      if (id.trim().isEmpty) return null;
      final number = arguments.orderNumber;
      if (number != null && number < 1) return _TrackedOrder(id, null);
      return _TrackedOrder(id, number);
    }
    if (arguments is AppRouteId) {
      if (arguments.value.trim().isEmpty) return null;
      return _TrackedOrder(arguments.value, null);
    }
    return null;
  }
}

/// Pedido já identificado. [orderNumber] nulo não é uma rota inválida.
final class _TrackedOrder {
  const _TrackedOrder(this.id, this.orderNumber);

  final String id;
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
  const _KnownOrder({
    required this.orderId,
    required this.orderNumber,
    required this.createViewModel,
    required this.routeObserver,
  });

  final String orderId;
  final int? orderNumber;
  final OrderTrackingViewModel Function(String orderId)? createViewModel;
  final RouteObserver<PageRoute<dynamic>>? routeObserver;

  @override
  Widget build(BuildContext context) {
    final label = publicOrderLabel(orderNumber);
    final create = createViewModel;
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
                if (create == null)
                  const DinnaEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Status ao vivo indisponível',
                    message: 'Este aplicativo ainda não atualiza o andamento do pedido.',
                    centered: false,
                  )
                else
                  OrderStatusTracker(
                    createViewModel: () => create(orderId),
                    routeObserver: routeObserver,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
