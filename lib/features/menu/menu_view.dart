import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/dinna_colors.dart';
import '../../core/domain/product.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import '../../shared/widgets/dinna_logo.dart';
import '../restaurant/order_format.dart';
import 'menu_view_model.dart';

/// Cardápio do cliente, na rota `/menu`.
///
/// O [MenuViewModel] nasce e morre com o State. A mesa chega pela navegação
/// e segue para o carrinho por [onOpenCart]. O Figma não tem ícone de carrinho
/// no header: o acesso volta com a barra do carrinho, ao adicionar itens (SCRUM-39).
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
    final colors = Theme.of(context).colorScheme;

    // Header do Figma: faixa branca com linha embaixo, sem seta de voltar.
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        backgroundColor: colors.surfaceContainerLowest,
        shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
        title: const DinnaLogo(size: 24),
        actions: [
          if (table != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _TableBadge(table: table),
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
    final sections = selected == null ? viewModel.categories : [selected];
    final headingStyle = Theme.of(context).textTheme.titleMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _CategoryChip(
                label: 'Todos',
                selected: selected == null,
                onSelected: () => viewModel.selectCategory(null),
              ),
              for (final category in viewModel.categories) ...[
                const SizedBox(width: 8),
                _CategoryChip(
                  label: _categoryLabel(category),
                  selected: selected == category,
                  onSelected: () => viewModel.selectCategory(category),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              for (final category in sections) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Text(_categoryLabel(category), style: headingStyle),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: viewModel.productsIn(category).length,
                    itemBuilder: (context, index) =>
                        _ProductCard(product: viewModel.productsIn(category)[index]),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Selo da mesa do Figma: fundo creme, borda e bolinha verde.
class _TableBadge extends StatelessWidget {
  const _TableBadge({required this.table});

  final String table;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: colors.secondary, shape: BoxShape.circle),
            child: const SizedBox.square(dimension: 8),
          ),
          const SizedBox(width: 6),
          Text(
            'Mesa $table',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip do Figma: selecionado em marrom escuro com texto claro, sem o ✓ do Material.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: colors.onSurface,
      backgroundColor: colors.surfaceContainerLowest,
      labelStyle: TextStyle(
        color: selected ? colors.surface : colors.onSurface,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => onSelected(),
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
    final (light, dark) = _placeholderFor(product.id);
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, dark],
        ),
      ),
    );

    final available = product.available;
    final image = imageUrl == null
        ? placeholder
        : Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (available)
                  image
                else
                  Opacity(
                    opacity: 0.55,
                    child: ColorFiltered(colorFilter: _grayscale, child: image),
                  ),
                if (!available)
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
                SizedBox(
                  height: 40,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: available ? colors.onSurface : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatOrderTotal(product.priceCents),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: available ? colors.primary : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tira a cor da imagem do produto esgotado, como no Figma.
const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Mesmo produto, mesma cor: o degradê sai do id, não da posição na lista.
(Color, Color) _placeholderFor(String productId) {
  final palette = DinnaColors.productPlaceholders;
  final seed = productId.codeUnits.fold(0, (sum, unit) => sum + unit);
  return palette[seed % palette.length];
}

/// A API manda a categoria como identificador (`bebidas`); a tela mostra "Bebidas".
String _categoryLabel(String category) =>
    category.isEmpty ? category : category[0].toUpperCase() + category.substring(1);
