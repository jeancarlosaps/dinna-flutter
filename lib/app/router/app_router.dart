import 'package:flutter/material.dart';

import '../../features/client/table/table_view.dart';
import '../../features/home/api_status_repository.dart';
import '../../features/home/home_view.dart';
import '../../features/home/home_view_model.dart';
import '../../features/restaurant/order_repository.dart';
import '../../features/restaurant/orders_queue_view.dart';
import '../../features/restaurant/orders_queue_view_model.dart';
import 'route_placeholder.dart';

/// Nomes de rota do app.
///
/// A home (`/`) é a rota inicial da fundação e o fluxo `GET /health`.
/// [clientFlow] e [restaurantFlow] nomeiam a jornada da R1, na ordem do
/// produto. A home, a mesa e a fila (`/restaurant`) têm tela. O restante
/// ainda usa [RoutePlaceholder].
///
/// A entrada do cliente é [table] (`/table`), o mesmo nome da `TableView`
/// na branch `feature/client-ui`. A integração coloca essa tela num case
/// próprio, antes do placeholder, e mantém o nome.
abstract final class AppRoutes {
  static const home = '/';

  /// Mesa. Entrada do cliente.
  static const table = '/table';

  /// Cardápio do cliente.
  static const menu = '/menu';

  /// Detalhe de produto. Argumento: [AppRouteId].
  static const product = '/product';

  /// Carrinho do cliente.
  static const cart = '/cart';

  /// Confirmação do pedido enviado pela mesa.
  static const order = '/order';

  /// Acompanhamento do pedido. Argumento: [AppRouteId].
  static const orderTracking = '/order/tracking';

  /// Fila de pedidos. Entrada do restaurante (painel).
  static const restaurant = '/restaurant';

  /// Detalhe do pedido na fila. Argumento: [AppRouteId].
  static const restaurantOrder = '/restaurant/order';

  /// Cardápio gerido pelo restaurante.
  static const restaurantMenu = '/restaurant/menu';

  /// Jornada do cliente, da mesa ao acompanhamento.
  static const clientFlow = <String>[table, menu, product, cart, order, orderTracking];

  /// Jornada do restaurante, da fila ao cardápio.
  static const restaurantFlow = <String>[restaurant, restaurantOrder, restaurantMenu];

  /// Rotas de detalhe. O id vai em [RouteSettings.arguments] como [AppRouteId].
  static const detailRoutes = <String>[product, orderTracking, restaurantOrder];
}

/// Id de produto ou de pedido passado em [RouteSettings.arguments].
///
/// O router não lê este valor. A View da rota é quem valida.
final class AppRouteId {
  const AppRouteId(this.value);

  final String value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || (other is AppRouteId && other.value == value);
  }

  @override
  int get hashCode => value.hashCode;
}

class AppRouter {
  AppRouter({
    required this.apiStatusRepository,
    required this.orderRepository,
    required this.routeObserver,
    this.pollDelay,
  });

  final ApiStatusRepository apiStatusRepository;
  final OrderRepository orderRepository;
  final RouteObserver<PageRoute<dynamic>> routeObserver;
  final Future<void> Function(Duration duration)? pollDelay;

  /// Sempre devolve uma rota. Nome fora do mapa cai em [UnknownRouteView].
  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(settings: settings, builder: (_) => _pageFor(settings.name));
  }

  Widget _pageFor(String? name) {
    return switch (name) {
      AppRoutes.home => HomeView(createViewModel: () => HomeViewModel(apiStatusRepository)),
      AppRoutes.table => const TableView(),
      AppRoutes.restaurant => OrdersQueueView(
        createViewModel: () => OrdersQueueViewModel(orderRepository, delay: pollDelay),
        routeObserver: routeObserver,
      ),
      _ when name != null && _isFlowRoute(name) => RoutePlaceholder(routeName: name),
      _ => UnknownRouteView(routeName: name),
    };
  }

  bool _isFlowRoute(String? name) {
    if (name == null) return false;
    return AppRoutes.clientFlow.contains(name) || AppRoutes.restaurantFlow.contains(name);
  }
}
