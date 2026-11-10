import 'package:flutter/material.dart';

import '../../core/domain/order.dart';
import '../../features/client/cart/cart_lines.dart';
import '../../features/client/cart/cart_repository.dart';
import '../../features/client/cart/cart_session.dart';
import '../../features/client/cart/cart_view.dart';
import '../../features/client/cart/cart_view_model.dart';
import '../../features/client/order/confirmed_cart_cleanup.dart';
import '../../features/client/order/last_order_session.dart';
import '../../features/client/order/order_confirmation_view.dart';
import '../../features/client/order/order_submission_view_model.dart';
import '../../features/client/order/order_tracking_view.dart';
import '../../features/client/order/order_tracking_view_model.dart';
import '../../features/client/table/table_view.dart';
import '../../features/home/api_status_repository.dart';
import '../../features/home/home_view.dart';
import '../../features/home/home_view_model.dart';
import '../../features/menu/menu_view.dart';
import '../../features/menu/menu_view_model.dart';
import '../../features/menu/product_detail_view_model.dart';
import '../../features/menu/product_repository.dart';
import '../../features/recommendation/recommendation_preferences_store.dart';
import '../../features/recommendation/recommendation_repository.dart';
import '../../features/recommendation/recommendation_request.dart';
import '../../features/recommendation/recommendation_view.dart';
import '../../features/recommendation/recommendation_view_model.dart';
import '../../features/restaurant/order_details_view.dart';
import '../../features/restaurant/order_details_view_model.dart';
import '../../features/restaurant/order_repository.dart';
import '../../features/restaurant/orders_queue_view.dart';
import '../../features/restaurant/orders_queue_view_model.dart';
import 'app_route_args.dart';
import 'route_placeholder.dart';

export 'app_route_args.dart';

/// Nomes de rota do app.
///
/// A home (`/`) é a rota inicial da fundação e o fluxo `GET /health`.
/// [clientFlow] e [restaurantFlow] nomeiam a jornada da R1, na ordem do
/// produto. A home, a mesa, o carrinho (`/cart`), a confirmação (`/order`),
/// o acompanhamento (`/order/tracking`), a fila (`/restaurant`) e o detalhe
/// do pedido (`/restaurant/order`) têm tela. [recommendation] abre a partir
/// do cardápio e fica fora de [clientFlow], para o placeholder continuar
/// só nas rotas da jornada que ainda não têm tela. O acompanhamento não
/// consulta status. O restante ainda usa [RoutePlaceholder].
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

  /// Formulário "Me ajuda a escolher". Argumento: mesa (`String`), como em [menu].
  ///
  /// Fora de [clientFlow]: quem abre é o cardápio, e a rota não ocupa o
  /// placeholder das telas ainda sem View.
  static const recommendation = '/recommendation';

  /// Detalhe de produto. Argumento: [AppRouteId].
  static const product = '/product';

  /// Carrinho do cliente.
  static const cart = '/cart';

  /// Confirmação do pedido já gravado. Argumento: [OrderConfirmationArgs].
  static const order = '/order';

  /// Acompanhamento do pedido. Argumento: [AppRouteId].
  ///
  /// A tela identifica o pedido e não atualiza o status.
  static const orderTracking = '/order/tracking';

  /// Fila de pedidos. Entrada do restaurante (painel).
  static const restaurant = '/restaurant';

  /// Detalhe do pedido na fila. Argumento: [RestaurantOrderArgs].
  static const restaurantOrder = '/restaurant/order';

  /// Cardápio gerido pelo restaurante.
  static const restaurantMenu = '/restaurant/menu';

  /// Jornada do cliente, da mesa ao acompanhamento.
  static const clientFlow = <String>[table, menu, product, cart, order, orderTracking];

  /// Jornada do restaurante, da fila ao cardápio.
  static const restaurantFlow = <String>[restaurant, restaurantOrder, restaurantMenu];

  /// Rotas de detalhe. O id vai em [RouteSettings.arguments] como [AppRouteId].
  /// Em [restaurantOrder], [RestaurantOrderArgs] leva o id e o pedido da fila.
  static const detailRoutes = <String>[product, orderTracking, restaurantOrder];
}

class AppRouter {
  AppRouter({
    required this.apiStatusRepository,
    required this.orderRepository,
    required this.productRepository,
    required this.cartLines,
    this.cartSession,
    required this.orderSubmission,
    this.lastOrderSession,
    required this.routeObserver,
    this.recommendationRepository,
    this.recommendationPreferencesStore,
    this.pollDelay,
    this.reconcileCart,
  }) : assert(cartSession == null || cartLines == null);

  final ApiStatusRepository apiStatusRepository;
  final OrderRepository orderRepository;
  final ProductRepository productRepository;

  /// Linhas da revisão. A implementação que sobrevive ao processo entra aqui.
  final CartLines? cartLines;
  final CartSession? cartSession;

  /// Envio da sessão. Sair de `/cart` não cria outro.
  final OrderSubmissionViewModel orderSubmission;
  final LastOrderSession? lastOrderSession;
  final RouteObserver<PageRoute<dynamic>> routeObserver;

  /// Nulo responde à rota com falha traduzida, sem consultar a API.
  final RecommendationRepository? recommendationRepository;

  /// Nulo deixa o formulário só na memória deste ViewModel.
  final RecommendationPreferencesStore? recommendationPreferencesStore;
  final Future<void> Function(Duration duration)? pollDelay;

  /// Concilia o carrinho confirmado uma vez. Nulo mantém a limpeza local da rota.
  final Future<bool> Function()? reconcileCart;

  /// Sempre devolve uma rota. Nome fora do mapa cai em [UnknownRouteView].
  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(settings: settings, builder: (_) => _pageFor(settings));
  }

  Widget _pageFor(RouteSettings settings) {
    final name = settings.name;
    return switch (name) {
      AppRoutes.home => HomeView(
        createViewModel: () => HomeViewModel(apiStatusRepository),
        lastOrderSession: lastOrderSession,
        onOpenLastOrder: _openConfirmation,
      ),
      AppRoutes.table => const TableView(),
      AppRoutes.menu => MenuView(
        createViewModel: () => MenuViewModel(productRepository),
        createDetailViewModel: (productId) =>
            ProductDetailViewModel(productRepository, productId: productId),
        cartSession: cartSession,
        table: _tableArgument(settings.arguments),
        onOpenCart: (context, table) =>
            Navigator.of(context).pushNamed(AppRoutes.cart, arguments: table),
        onOpenRecommendation: (context, table) =>
            Navigator.of(context).pushNamed(AppRoutes.recommendation, arguments: table),
      ),
      AppRoutes.recommendation => RecommendationView(
        createViewModel: () => RecommendationViewModel(
          recommendationRepository ?? const _MissingRecommendationRepository(),
          products: productRepository,
          cartSession: cartSession,
          preferencesStore: recommendationPreferencesStore,
          table: _tableArgument(settings.arguments),
        ),
        routeObserver: routeObserver,
        onShowMenu: (context) => Navigator.of(context).pop(),
        onOpenCart: (context) =>
            Navigator.of(context)
                .pushNamed(AppRoutes.cart, arguments: _tableArgument(settings.arguments)),
      ),
      AppRoutes.cart => CartView(
        createViewModel: () => cartSession == null
            ? CartViewModel(productRepository, lines: cartLines!)
            : CartViewModel.persisted(productRepository, session: cartSession!),
        cartSession: cartSession,
        submission: orderSubmission,
        table: _cartTable(settings.arguments),
        reviewOnly: _cartReviewOnly(settings.arguments),
        onOpenMenu: (context) =>
            Navigator.of(context)
                .pushNamed(AppRoutes.menu, arguments: _tableArgument(settings.arguments)),
        onOrderConfirmed: _openConfirmation,
        reconcileCart: reconcileCart,
      ),
      AppRoutes.order => OrderConfirmationView(
        onTrack: _openTracking,
        onGoHome: _goHome,
        onStartAnother: _startAnotherOrder,
        submission: orderSubmission,
      ),
      AppRoutes.orderTracking => OrderTrackingView(
        createViewModel: (orderId) => OrderTrackingViewModel(orderRepository, orderId: orderId),
        routeObserver: routeObserver,
      ),
      AppRoutes.restaurant => OrdersQueueView(
        createViewModel: () => OrdersQueueViewModel(orderRepository, delay: pollDelay),
        routeObserver: routeObserver,
        onOrderSelected: _openOrder,
      ),
      AppRoutes.restaurantOrder => OrderDetailsView(
        createViewModel: (order) =>
            OrderDetailsViewModel(productRepository, orderRepository, order: order),
      ),
      _ when name != null && _isFlowRoute(name) => RoutePlaceholder(routeName: name),
      _ => UnknownRouteView(routeName: name),
    };
  }

  String? _cartTable(Object? arguments) {
    if (arguments is CartRouteArgs) return _tableArgument(arguments.table);
    return _tableArgument(arguments);
  }

  bool _cartReviewOnly(Object? arguments) {
    return arguments is CartRouteArgs && arguments.reviewOnly;
  }

  /// A navegação entrega a mesa como [String]. Outro argumento não é mesa.
  String? _tableArgument(Object? arguments) {
    if (arguments is! String) return null;
    final table = arguments.trim();
    return table.isEmpty ? null : table;
  }

  Future<void> _openConfirmation(BuildContext context, Order order) async {
    await Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.order,
      (route) => route.settings.name == AppRoutes.home,
      arguments: OrderConfirmationArgs(order: order),
    );
  }

  void _goHome(BuildContext context) {
    Navigator.of(context)
        .popUntil((route) => route.settings.name == AppRoutes.home || route.isFirst);
  }

  Future<void> _startAnotherOrder(BuildContext context) async {
    if (!orderSubmission.canBeginAnotherOrder) return;
    if (orderSubmission.legacyCartRemaining) {
      final cart = cartSession;
      if (cart != null && cart.isReady && cart.read().isNotEmpty) {
        if (!context.mounted) return;
        await Navigator.of(context).pushNamed(
          AppRoutes.cart,
          arguments: CartRouteArgs(table: orderSubmission.order?.table, reviewOnly: true),
        );
        return;
      }
    }
    final reconcile = reconcileCart;
    if (reconcile != null) {
      if (!await reconcile()) return;
    } else {
      final confirmed = orderSubmission.confirmedItems;
      final cart = cartSession;
      if (cart != null && confirmed != null && !orderSubmission.cartReconciled) {
        final intentId = orderSubmission.intentId;
        if (intentId == null) return;
        try {
          if (!cart.isReady) await cart.restore();
          final result = await cart.reconcileConfirmed(
            intentId: intentId,
            confirmedItems: confirmed,
          );
          if (result.outcome == CartReconciliation.unresolved && result.items.isNotEmpty) {
            orderSubmission.noteLegacyCartRemaining(true);
            return;
          }
        } catch (_) {
          return;
        }
      }
      final memory = cartLines;
      if (cart == null && memory != null && confirmed != null && !orderSubmission.cartReconciled) {
        final current = memory.read();
        if (!memory.replace(current, withoutConfirmedItems(current, confirmed))) return;
      }
    }
    await orderSubmission.beginAnotherOrder();
    if (!context.mounted || orderSubmission.status != OrderSubmissionStatus.idle) return;
    await Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.table, (route) => route.settings.name == AppRoutes.home);
  }

  Future<void> _openTracking(BuildContext context, Order order) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.orderTracking,
      arguments: OrderTrackingArgs(id: AppRouteId(order.id), orderNumber: order.orderNumber),
    );
  }

  Future<Object?> _openOrder(BuildContext context, Order order) {
    return Navigator.of(context).pushNamed(
      AppRoutes.restaurantOrder,
      arguments: RestaurantOrderArgs(id: AppRouteId(order.id), order: order),
    );
  }

  bool _isFlowRoute(String? name) {
    if (name == null) return false;
    return AppRoutes.clientFlow.contains(name) || AppRoutes.restaurantFlow.contains(name);
  }
}

/// Usada quando o app de teste não injeta a recomendação. O formulário abre
/// e o envio cai na mensagem da tela, sem HTTP.
final class _MissingRecommendationRepository implements RecommendationRepository {
  const _MissingRecommendationRepository();

  @override
  Future<RecommendationAttempt> recommend(RecommendationRequest request) async {
    return const RecommendationAttempt.failed(
      RecommendationFailure.unavailable,
      title: RecommendationRepository.failureTitle,
      message: RecommendationRepository.failureMessage,
    );
  }
}
