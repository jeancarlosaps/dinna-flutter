import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/order.dart';
import 'orders_queue_view.dart';
import 'orders_queue_view_model.dart';
import 'product_catalog_view.dart';
import 'product_catalog_view_model.dart';
import 'restaurant_rail.dart';

/// Pedidos e produtos no mesmo lugar. A troca de seção não empurra outra rota.
class RestaurantShell extends StatefulWidget {
  const RestaurantShell({
    super.key,
    required this.createQueue,
    required this.createCatalog,
    required this.initialSection,
    this.routeObserver,
    this.onOrderSelected,
    this.buildOrderPane,
    this.onLeave,
  });

  final OrdersQueueViewModel Function() createQueue;
  final ProductCatalogViewModel Function() createCatalog;
  final RestaurantSection initialSection;
  final RouteObserver<PageRoute<dynamic>>? routeObserver;
  final FutureOr<Object?> Function(BuildContext context, Order order)? onOrderSelected;
  final Widget Function(BuildContext context, Order order, ValueChanged<Order> onChanged)?
  buildOrderPane;
  final void Function(BuildContext context)? onLeave;

  @override
  State<RestaurantShell> createState() => _RestaurantShellState();
}

class _RestaurantShellState extends State<RestaurantShell> {
  late RestaurantSection _section = widget.initialSection;

  void _show(RestaurantSection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _section == RestaurantSection.orders ? 0 : 1,
      children: [
        OrdersQueueView(
          createViewModel: widget.createQueue,
          routeObserver: widget.routeObserver,
          onOrderSelected: widget.onOrderSelected,
          onOpenProducts: (_) => _show(RestaurantSection.products),
          buildOrderPane: widget.buildOrderPane,
          onLeave: widget.onLeave,
          active: _section == RestaurantSection.orders,
        ),
        ProductCatalogView(
          createViewModel: widget.createCatalog,
          onOpenOrders: (_) => _show(RestaurantSection.orders),
          onLeave: widget.onLeave,
        ),
      ],
    );
  }
}
