import 'package:flutter/material.dart';

import '../features/client/cart/cart_lines.dart';
import '../features/client/order/order_submission_view_model.dart';
import '../features/home/api_status_repository.dart';
import '../features/menu/product_repository.dart';
import '../features/restaurant/order_repository.dart';
import 'router/app_router.dart';
import 'theme/dinna_theme.dart';

class DinnaApp extends StatefulWidget {
  const DinnaApp({
    super.key,
    required this.apiStatusRepository,
    required this.orderRepository,
    required this.productRepository,
    this.cartLines,
    this.routeObserver,
    this.pollDelay,
  });

  final ApiStatusRepository apiStatusRepository;
  final OrderRepository orderRepository;
  final ProductRepository productRepository;

  /// Nula cria [ProcessCartLines] neste State. Testes e o `main` podem injetar.
  final CartLines? cartLines;

  /// Instância ligada à fila. Nula cria um observer estável neste State.
  final RouteObserver<PageRoute<dynamic>>? routeObserver;

  /// Relógio do polling. Nulo usa [Future.delayed]. Testes injetam um atraso
  /// sem timer para o `pumpAndSettle` conseguir encerrar.
  final Future<void> Function(Duration duration)? pollDelay;

  @override
  State<DinnaApp> createState() => _DinnaAppState();
}

class _DinnaAppState extends State<DinnaApp> {
  late final RouteObserver<PageRoute<dynamic>> _routeObserver;
  late final CartLines _cartLines;
  late final OrderSubmissionViewModel _submission;

  @override
  void initState() {
    super.initState();
    _routeObserver = widget.routeObserver ?? RouteObserver<PageRoute<dynamic>>();
    _cartLines = widget.cartLines ?? ProcessCartLines();
    _submission = OrderSubmissionViewModel(widget.orderRepository);
  }

  @override
  void dispose() {
    _submission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dinna',
      debugShowCheckedModeBanner: false,
      theme: DinnaTheme.light(),
      navigatorObservers: [_routeObserver],
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRouter(
        apiStatusRepository: widget.apiStatusRepository,
        orderRepository: widget.orderRepository,
        productRepository: widget.productRepository,
        cartLines: _cartLines,
        orderSubmission: _submission,
        routeObserver: _routeObserver,
        pollDelay: widget.pollDelay,
      ).onGenerateRoute,
    );
  }
}
