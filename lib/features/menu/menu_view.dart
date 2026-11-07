import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/domain/product.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import '../../shared/widgets/dinna_logo.dart';
import '../restaurant/order_format.dart';
import 'menu_view_model.dart';
import 'product_detail_view.dart';
import 'product_detail_view_model.dart';
import 'product_image.dart';

/// Cardápio do cliente, na rota `/menu`.
///
/// O [MenuViewModel] nasce e morre com o State. A mesa chega pela navegação
/// e segue para o carrinho por [onOpenCart]. O Figma não tem ícone de carrinho
/// no header: o acesso volta com a barra do carrinho, ao adicionar itens (SCRUM-39).
///
/// Tocar um produto abre o detalhe em bottom sheet com [createDetailViewModel].
/// [onOpenRecommendation] abre "Me ajuda a escolher" sem trocar o cardápio.
class MenuView extends StatefulWidget {
  const MenuView({
    super.key,
    required this.createViewModel,
    required this.onOpenCart,
    this.createDetailViewModel,
    this.onOpenRecommendation,
    this.table,
  });

  final MenuViewModel Function() createViewModel;

  /// Cria o ViewModel do detalhe para o id tocado. Nulo: o card não abre o detalhe.
  final ProductDetailViewModel Function(String productId)? createDetailViewModel;
  final void Function(BuildContext context, String? table) onOpenCart;

  /// Abre a recomendação com a mesma mesa. Nulo esconde o atalho.
  final void Function(BuildContext context, String? table)? onOpenRecommendation;

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

  void Function(Product)? get _openProduct {
    final createDetail = widget.createDetailViewModel;
    if (createDetail == null) return null;
    return (product) => showProductDetail(context, createViewModel: () => createDetail(product.id));
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final colors = Theme.of(context).colorScheme;
    final openRecommendation = widget.onOpenRecommendation;

    // Header do Figma: faixa branca com linha embaixo, sem seta de voltar.
    // A altura acompanha o selo quando o texto da mesa cresce.
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: _toolbarHeight(context, table),
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        backgroundColor: colors.surfaceContainerLowest,
        shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
        title: const DinnaLogo(size: 24),
        actions: [
          if (table != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _TableBadge(table: table, maxWidth: _badgeMaxWidth(context)),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (openRecommendation != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: OutlinedButton(
                  onPressed: () => openRecommendation(context, table),
                  child: const Text('Me ajuda a escolher'),
                ),
              ),
            Expanded(
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => switch (_viewModel.status) {
                  MenuStatus.loading => const Center(child: CircularProgressIndicator()),
                  MenuStatus.failed => _ScrollableStatus(
                    child: DinnaEmptyState(
                      icon: Icons.wifi_off,
                      title: 'Não foi possível carregar o cardápio',
                      message: _viewModel.errorMessage ?? MenuViewModel.fallbackErrorMessage,
                      actionLabel: 'Tentar de novo',
                      onAction: _viewModel.load,
                    ),
                  ),
                  MenuStatus.ready when _viewModel.isEmpty => const _ScrollableStatus(
                    child: DinnaEmptyState(
                      icon: Icons.restaurant_menu,
                      title: 'Cardápio vazio',
                      message: 'O restaurante ainda não cadastrou pratos.',
                    ),
                  ),
                  MenuStatus.ready => _MenuContent(
                    viewModel: _viewModel,
                    onOpenProduct: _openProduct,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuContent extends StatelessWidget {
  const _MenuContent({required this.viewModel, required this.onOpenProduct});

  final MenuViewModel viewModel;
  final ValueChanged<Product>? onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final selected = viewModel.selectedCategory;
    final sections = selected == null ? viewModel.categories : [selected];
    final headingStyle = Theme.of(context).textTheme.titleMedium;

    return LayoutBuilder(
      builder: (context, constraints) {
        final grouped = viewModel.groupedProducts();
        final grid = _gridMetrics(context, constraints.maxWidth - 32);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryStrip(viewModel: viewModel),
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
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: grid.count,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: grid.extent,
                        ),
                        itemCount: (grouped[category] ?? const []).length,
                        itemBuilder: (context, index) =>
                            _ProductCard(product: grouped[category]![index], onTap: onOpenProduct),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Erro e cardápio vazio rolam em tela baixa e ficam centralizados quando cabem.
class _ScrollableStatus extends StatelessWidget {
  const _ScrollableStatus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}

/// A faixa cresce com o chip. A rolagem continua horizontal.
class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.viewModel});

  final MenuViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final selected = viewModel.selectedCategory;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
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
      ),
    );
  }
}

/// Altura do header: 56 px na escala normal. Com texto ampliado, cabe a marca e o selo.
double _toolbarHeight(BuildContext context, String? table) {
  final scaler = MediaQuery.textScalerOf(context);
  final logoHeight = scaler.scale(24);
  var needed = logoHeight + 8;
  if (table != null) {
    final badge = _badgeTextHeight(context, table) + 14;
    needed = math.max(needed, badge + 8);
  }
  return math.max(kToolbarHeight, needed);
}

/// Largura restante do header depois da marca, do espaçamento e do padding.
double _badgeMaxWidth(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final logo = TextPainter(
    text: const TextSpan(
      text: 'dinna.',
      style: TextStyle(
        fontSize: 24,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: 24 * -0.035,
      ),
    ),
    textDirection: Directionality.of(context),
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final padding = MediaQuery.paddingOf(context);
  final width = MediaQuery.sizeOf(context).width - padding.left - padding.right;
  return math.max(48, width - logo.width - 48);
}

double _badgeTextHeight(BuildContext context, String table) {
  final style = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
  final inner = math.max(1.0, _badgeMaxWidth(context) - 40);
  final painter = TextPainter(
    text: TextSpan(text: 'Mesa $table', style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: inner);
  return painter.height;
}

/// Colunas e altura do card. Na escala 1 a proporção segue o limite de 220 px.
/// Texto ampliado reduz colunas até o selo "Esgotado" caber na largura.
({int count, double extent}) _gridMetrics(BuildContext context, double gridWidth) {
  const maxTile = 220.0;
  const spacing = 12.0;
  const aspect = 0.78;
  final width = math.max(gridWidth, 1.0);
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final badge = TextPainter(
    text: TextSpan(text: 'Esgotado', style: theme.textTheme.labelSmall),
    textDirection: Directionality.of(context),
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final minTile = badge.width + 32;

  var count = (width / (maxTile + spacing)).ceil();
  count = math.max(1, count);
  while (count > 1) {
    final tile = (width - spacing * (count - 1)) / count;
    if (tile + 0.5 >= minTile) break;
    count -= 1;
  }
  final usable = math.max(0.0, width - spacing * (count - 1));
  final tileWidth = usable / count;
  final base = tileWidth / aspect;

  final nameStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
  final priceStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
  final textWidth = math.max(tileWidth - 28, 1.0);
  final extra =
      math.max(
        0.0,
        _textBlock(context, nameStyle, scaler, lines: 2, maxWidth: textWidth) -
            _textBlock(context, nameStyle, TextScaler.noScaling, lines: 2, maxWidth: textWidth),
      ) +
      math.max(
        0.0,
        _textBlock(context, priceStyle, scaler, lines: 1, maxWidth: textWidth) -
            _textBlock(context, priceStyle, TextScaler.noScaling, lines: 1, maxWidth: textWidth),
      );
  // O Text fica um pouco mais alto que o TextPainter quando a escala passa de 1.
  final scale = scaler.scale(1);
  final slack = scale <= 1 ? 0.0 : 8 * (scale - 1);
  return (count: count, extent: base + extra + slack);
}

double _textBlock(
  BuildContext context,
  TextStyle? style,
  TextScaler scaler, {
  required int lines,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: lines == 1 ? 'Ag' : 'Ag\nAg', style: style),
    textDirection: Directionality.of(context),
    textScaler: scaler,
    maxLines: lines,
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

/// Selo da mesa do Figma: fundo creme, borda e bolinha verde.
class _TableBadge extends StatelessWidget {
  const _TableBadge({required this.table, required this.maxWidth});

  final String table;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
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
            Flexible(
              child: Text(
                'Mesa $table',
                softWrap: true,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
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
  const _ProductCard({required this.product, required this.onTap});

  final Product product;
  final ValueChanged<Product>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final available = product.available;
    final tap = onTap;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tap == null ? null : () => tap(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(product: product),
                  if (!available)
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.onSurface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Esgotado',
                            softWrap: true,
                            style: theme.textTheme.labelSmall?.copyWith(color: colors.surface),
                          ),
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: available ? colors.onSurface : colors.onSurfaceVariant,
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
      ),
    );
  }
}

/// A API manda a categoria como identificador (`bebidas`); a tela mostra "Bebidas".
String _categoryLabel(String category) =>
    category.isEmpty ? category : category[0].toUpperCase() + category.substring(1);
