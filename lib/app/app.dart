import 'dart:async';

import 'package:flutter/material.dart';

import '../features/client/cart/cart_lines.dart';
import '../features/client/cart/cart_session.dart';
import '../features/client/order/confirmed_cart_cleanup.dart';
import '../features/client/order/order_intent_store.dart';
import '../features/client/order/order_submission_view_model.dart';
import '../features/home/api_status_repository.dart';
import '../features/menu/product_repository.dart';
import '../features/recommendation/recommendation_preferences_store.dart';
import '../features/recommendation/recommendation_repository.dart';
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
    this.cartSession,
    this.orderIntentStore,
    this.recommendationRepository,
    this.recommendationPreferencesStore,
    this.routeObserver,
    this.pollDelay,
  }) : assert(cartSession == null || cartLines == null);

  final ApiStatusRepository apiStatusRepository;
  final OrderRepository orderRepository;
  final ProductRepository productRepository;

  /// Compatibilidade para fluxos em memória usados por testes. Produção injeta
  /// [cartSession] e não cria um segundo carrinho.
  final CartLines? cartLines;

  /// Sessão SQLite compartilhada pela revisão do carrinho e pela inclusão.
  final CartSession? cartSession;

  /// Nula guarda a intenção de pedido só na memória desta sessão.
  final OrderIntentStore? orderIntentStore;

  /// Nula deixa a rota de recomendação sem HTTP. O `main` injeta a implementação.
  final RecommendationRepository? recommendationRepository;

  /// Nula abre "Me ajuda a escolher" sem gravar as respostas. O `main` injeta o arquivo.
  final RecommendationPreferencesStore? recommendationPreferencesStore;

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
  CartLines? _cartLines;
  CartSession? _cartSession;
  late final OrderSubmissionViewModel _submission;
  ConfirmedCartCleanup? _cartCleanup;

  @override
  void initState() {
    super.initState();
    _routeObserver = widget.routeObserver ?? RouteObserver<PageRoute<dynamic>>();
    _cartSession = widget.cartSession;
    _cartLines = _cartSession == null ? widget.cartLines ?? ProcessCartLines() : null;
    final cartSession = _cartSession;
    if (cartSession != null) unawaited(_restoreCart(cartSession));
    _submission = OrderSubmissionViewModel(
      widget.orderRepository,
      intentStore: widget.orderIntentStore,
    );
    _cartCleanup = ConfirmedCartCleanup(
      submission: _submission,
      session: _cartSession,
      lines: _cartLines,
    )..attach();
    unawaited(_submission.restore());
  }

  Future<void> _restoreCart(CartSession session) async {
    try {
      await session.restore();
    } catch (_) {
      // CartSession conserva o erro para a tela distinguir falha de carrinho vazio.
    }
  }

  @override
  void dispose() {
    _cartCleanup?.detach();
    _cartSession?.dispose();
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
        cartSession: _cartSession,
        orderSubmission: _submission,
        routeObserver: _routeObserver,
        recommendationRepository: widget.recommendationRepository,
        recommendationPreferencesStore: widget.recommendationPreferencesStore,
        pollDelay: widget.pollDelay,
      ).onGenerateRoute,
    );
  }
}
