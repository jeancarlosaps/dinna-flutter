import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/product.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import '../../shared/widgets/dinna_logo.dart';
import '../restaurant/order_format.dart';
import 'menu_view_model.dart';

/// Cardápio do cliente, na rota `/menu`.
///
/// O [MenuViewModel] nasce e morre com o State. A mesa chega pela navegação
/// e segue para o carrinho por [onOpenCart].
class MenuView extends StatefulWidget {
  const MenuView({super.key, required this.createViewModel, required this.onOpenCart, this.table});

  final MenuViewModel Function() createViewModel;
  final void Function(BuildContext context, String? table) onOpenCart;

  /// Mesa recebida da tela da mesa. Ausente quando o cardápio abre por outro caminho.
  final String? table;

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> {
  late final MenuViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.createViewModel();
    unawaited(_viewModel.load());
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;

    return Scaffold(
      appBar: AppBar(
        title: const DinnaLogo(size: 24),
        actions: [
          if (table != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(label: Text('Mesa $table')),
            ),
          IconButton(
            tooltip: 'Carrinho',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => widget.onOpenCart(context, table),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => switch (_viewModel.status) {
          MenuStatus.loading => const Center(child: CircularProgressIndicator()),
          MenuStatus.failed => DinnaEmptyState(
            icon: Icons.wifi_off,
            title: 'Não foi possível carregar o cardápio',
            message: _viewModel.errorMessage ?? MenuViewModel.fallbackErrorMessage,
            actionLabel: 'Tentar de novo',
            onAction: _viewModel.load,
          ),
          MenuStatus.ready when _viewModel.isEmpty => const DinnaEmptyState(
            icon: Icons.restaurant_menu,
            title: 'Cardápio vazio',
            message: 'O restaurante ainda não cadastrou pratos.',
          ),
          MenuStatus.ready => _MenuContent(viewModel: _viewModel),
        },
      ),
    );
  }
}

class _MenuContent extends StatelessWidget {
  const _MenuContent({required this.viewModel});

  final MenuViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final selected = viewModel.selectedCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: selected == null,
                onSelected: (_) => viewModel.selectCategory(null),
              ),
              for (final category in viewModel.categories) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(category),
                  selected: selected == category,
                  onSelected: (_) => viewModel.selectCategory(category),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: viewModel.visibleProducts.length,
            itemBuilder: (context, index) =>
                _ProductCard(product: viewModel.visibleProducts[index]),
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final imageUrl = product.imageUrl;
    final placeholder = ColoredBox(
      color: colors.primaryContainer,
      child: Icon(Icons.restaurant, color: colors.primary),
    );

    return Opacity(
      opacity: product.available ? 1 : 0.6,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl == null)
                    placeholder
                  else
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => placeholder,
                    ),
                  if (!product.available)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.onSurface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Esgotado',
                          style: theme.textTheme.labelSmall?.copyWith(color: colors.surface),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatOrderTotal(product.priceCents),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
