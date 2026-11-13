import 'package:flutter/material.dart';

import '../../shared/widgets/dinna_logo.dart';

/// Seção visível no trilho do painel.
enum RestaurantSection { orders, products }

/// Trilho estreito do painel. No celular ele não entra na árvore.
class RestaurantRail extends StatelessWidget {
  const RestaurantRail({
    super.key,
    required this.section,
    this.onOrders,
    this.onProducts,
    this.onLeave,
  });

  final RestaurantSection section;
  final VoidCallback? onOrders;
  final VoidCallback? onProducts;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 88,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              InkWell(
                onTap: onLeave,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(padding: EdgeInsets.all(8), child: DinnaLogo(size: 16)),
              ),
              const SizedBox(height: 20),
              _RailButton(
                label: 'Pedidos',
                icon: Icons.receipt_long_outlined,
                selected: section == RestaurantSection.orders,
                onTap: onOrders,
              ),
              const SizedBox(height: 8),
              _RailButton(
                label: 'Produtos',
                icon: Icons.restaurant_menu_outlined,
                selected: section == RestaurantSection.products,
                onTap: onProducts,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SizedBox(width: 44, height: 44, child: Icon(icon, color: color, size: 22)),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
