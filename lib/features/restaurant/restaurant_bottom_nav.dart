import 'package:flutter/material.dart';

import '../../app/theme/dinna_colors.dart';
import 'restaurant_rail.dart';

/// Barra inferior do painel no celular: Pedidos e Produtos.
class RestaurantBottomNav extends StatelessWidget {
  const RestaurantBottomNav({super.key, required this.section, this.onOrders, this.onProducts});

  final RestaurantSection section;
  final VoidCallback? onOrders;
  final VoidCallback? onProducts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = section == RestaurantSection.orders ? 0 : 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: DinnaColors.line,
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(color: selected ? DinnaColors.brown : DinnaColors.muted);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? DinnaColors.brown : DinnaColors.muted,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: current,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          indicatorColor: DinnaColors.line,
          onDestinationSelected: (index) {
            if (index == current) return;
            if (index == 0) onOrders?.call();
            if (index == 1) onProducts?.call();
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Pedidos',
            ),
            NavigationDestination(
              icon: Icon(Icons.restaurant_menu_outlined),
              selectedIcon: Icon(Icons.restaurant_menu),
              label: 'Produtos',
            ),
          ],
        ),
      ),
    );
  }
}
