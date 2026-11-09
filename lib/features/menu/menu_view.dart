import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/domain/product.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import '../../shared/widgets/dinna_logo.dart';
import '../client/cart/cart_session.dart';
import '../restaurant/order_format.dart';
import 'menu_view_model.dart';
import 'product_detail_view.dart';
import 'product_detail_view_model.dart';
import 'product_image.dart';

/// Cardápio do cliente, na rota `/menu`.
///
/// O [MenuViewModel] nasce e morre com o State. A mesa chega pela navegação
/// e segue para o carrinho por [onOpenCart]. O header não leva ícone de
/// carrinho: com itens na [CartSession], a barra inferior abre o mesmo
/// carrinho e mostra a quantidade e o total estimados.
///
/// Tocar um produto abre o detalhe em bottom sheet com [createDetailViewModel].
/// O campo de busca filtra os cards pelo nome, junto com a categoria escolhida.
/// [onOpenRecommendation] abre "Me ajuda a escolher" sem trocar o cardápio.
class MenuView extends StatefulWidget {
  const MenuView({
    super.key,
    required this.createViewModel,
    required this.onOpenCart,
    this.createDetailViewModel,
    this.cartSession,
    this.onOpenRecommendation,
    this.table,
  });

  final MenuViewModel Function() createViewModel;

  /// Cria o ViewModel do detalhe para o id tocado. Nulo: o card não abre o detalhe.
  final ProductDetailViewModel Function(String productId)? createDetailViewModel;

  /// Sessão compartilhada que confirma a inclusão no armazenamento local.
  final CartSession? cartSession;
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
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _viewModel = widget.createViewModel();
    widget.cartSession?.addListener(_onCartSessionChanged);
    unawaited(_viewModel.load());
  }

  void _onCartSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.cartSession?.removeListener(_onCartSessionChanged);
    _searchController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    _viewModel.search('');
  }

  void Function(Product)? get _openProduct {
    final createDetail = widget.createDetailViewModel;
    final session = widget.cartSession;
    if (createDetail == null || (session != null && !session.isReady)) return null;
    return (product) => showProductDetail(
      context,
      createViewModel: () => createDetail(product.id),
      onAdd: session == null ? null : (product, quantity) => _addProduct(product, quantity),
    );
  }

  Future<void> _addProduct(Product product, int quantity) async {
    final session = widget.cartSession;
    if (session == null || !session.isReady) {
      throw StateError('O carrinho ainda não foi restaurado');
    }
    await session.addLine(productId: product.id, quantity: quantity);
  }

  Future<void> _retryCartRestore(CartSession session) async {
    try {
      await session.restore();
    } catch (_) {
      // A mensagem de erro fica visível na faixa para permitir nova tentativa.
    }
  }

  /// Quantidade e total da sessão já restaurada. Carrinho vazio ou ainda
  /// indisponível não mostra a barra. O total só aparece quando cada item tem
  /// preço no cardápio carregado.
  _CartSummary? _cartSummary() {
    final session = widget.cartSession;
    if (session == null || !session.isReady) return null;
    final items = session.read();
    if (items.isEmpty) return null;

    var count = 0;
    int? totalCents = _viewModel.status == MenuStatus.ready ? 0 : null;
    final prices = totalCents == null ? const <String, int>{} : _pricesById();
    for (final item in items) {
      count += item.quantity;
      if (totalCents == null) continue;
      final price = prices[item.productId];
      if (price == null) {
        totalCents = null;
        continue;
      }
      totalCents += price * item.quantity;
    }
    return _CartSummary(itemCount: count, totalCents: totalCents);
  }

  Map<String, int> _pricesById() {
    final prices = <String, int>{};
    for (final products in _viewModel.groupedProducts().values) {
      for (final product in products) {
        prices[product.id] = product.priceCents;
      }
    }
    return prices;
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final colors = Theme.of(context).colorScheme;
    final openRecommendation = widget.onOpenRecommendation;

    // Header do Figma: faixa branca com linha embaixo, sem seta de voltar.
    // A altura acompanha o selo quando o texto da mesa cresce.
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final summary = _cartSummary();
        final header = _headerLayout(context, table);
        final displacedTable = table != null && !header.badgeInToolbar
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TableBadge(table: table, maxWidth: header.badgeMaxWidth),
                ),
              )
            : null;
        final recommendation = _recommendationButton(context, table, openRecommendation);
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: header.toolbarHeight,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            backgroundColor: colors.surfaceContainerLowest,
            shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
            title: header.stackBadge
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DinnaLogo(size: 24),
                      const SizedBox(height: 8),
                      _TableBadge(table: table!, maxWidth: header.badgeMaxWidth),
                    ],
                  )
                : const DinnaLogo(size: 24),
            actions: [
              if (header.badgeInToolbar && !header.stackBadge)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _TableBadge(table: table!, maxWidth: header.badgeMaxWidth),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: summary == null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.cartSession?.restoreError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Não foi possível recuperar o carrinho salvo.')),
                        TextButton(
                          onPressed: widget.cartSession!.isRestoring
                              ? null
                              : () => unawaited(_retryCartRestore(widget.cartSession!)),
                          child: widget.cartSession!.isRestoring
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: switch (_viewModel.status) {
                    MenuStatus.loading => const Center(child: CircularProgressIndicator()),
                    MenuStatus.failed => _ScrollableStatus(
                      header: _statusHeader(displacedTable, recommendation),
                      child: DinnaEmptyState(
                        icon: Icons.wifi_off,
                        title: 'Não foi possível carregar o cardápio',
                        message: _viewModel.errorMessage ?? MenuViewModel.fallbackErrorMessage,
                        actionLabel: 'Tentar de novo',
                        onAction: _viewModel.load,
                        centered: false,
                      ),
                    ),
                    MenuStatus.ready when _viewModel.isEmpty => _ScrollableStatus(
                      header: _statusHeader(displacedTable, recommendation),
                      child: const DinnaEmptyState(
                        icon: Icons.restaurant_menu,
                        title: 'Cardápio vazio',
                        message: 'O restaurante ainda não cadastrou pratos.',
                        centered: false,
                      ),
                    ),
                    MenuStatus.ready => _MenuContent(
                      viewModel: _viewModel,
                      searchController: _searchController,
                      onClearSearch: _clearSearch,
                      onOpenProduct: _openProduct,
                      banner: displacedTable,
                      recommendation: recommendation,
                    ),
                  },
                ),
              ],
            ),
          ),
          bottomNavigationBar: summary == null
              ? null
              : _CartAccessBar(
                  summary: summary,
                  table: table,
                  onPressed: () => widget.onOpenCart(context, table),
                ),
        );
      },
    );
  }
}

class _CartSummary {
  const _CartSummary({required this.itemCount, required this.totalCents});

  final int itemCount;
  final int? totalCents;

  String get countLabel => itemCount == 1 ? '1 item' : '$itemCount itens';

  String get label {
    final total = totalCents;
    if (total == null) return 'Ver carrinho · $countLabel';
    return 'Ver carrinho · $countLabel · ${formatOrderTotal(total)}';
  }
}

/// Ação fixa do cardápio. A rolagem fica no corpo; a safe area fica nesta faixa.
class _CartAccessBar extends StatelessWidget {
  const _CartAccessBar({required this.summary, required this.table, required this.onPressed});

  final _CartSummary summary;
  final String? table;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shown = _cartLabelThatFits(
                  context,
                  summary.label,
                  constraints.maxWidth,
                  table,
                );
                final shortened = shown != summary.label;
                return FilledButton(
                  onPressed: onPressed,
                  child: Text(
                    shown,
                    textAlign: TextAlign.center,
                    maxLines: shortened ? 1 : null,
                    overflow: shortened ? TextOverflow.fade : null,
                    semanticsLabel: shortened ? summary.label : null,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuContent extends StatelessWidget {
  const _MenuContent({
    required this.viewModel,
    required this.searchController,
    required this.onClearSearch,
    required this.onOpenProduct,
    this.banner,
    this.recommendation,
  });

  final MenuViewModel viewModel;
  final TextEditingController searchController;
  final VoidCallback onClearSearch;
  final ValueChanged<Product>? onOpenProduct;
  final Widget? banner;
  final Widget? recommendation;

  @override
  Widget build(BuildContext context) {
    final selected = viewModel.selectedCategory;
    final headingStyle = Theme.of(context).textTheme.titleMedium;

    return LayoutBuilder(
      builder: (context, constraints) {
        final grouped = viewModel.groupedMatches();
        final sections = [
          for (final category in selected == null ? viewModel.categories : [selected])
            if ((grouped[category] ?? const []).isNotEmpty) category,
        ];
        final grid = _gridMetrics(context, constraints.maxWidth - 32);
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (recommendation != null) SliverToBoxAdapter(child: recommendation),
            if (banner != null) SliverToBoxAdapter(child: banner),
            SliverToBoxAdapter(
              child: _SearchField(
                controller: searchController,
                onChanged: viewModel.search,
                onClear: onClearSearch,
              ),
            ),
            SliverToBoxAdapter(child: _CategoryStrip(viewModel: viewModel)),
            if (sections.isEmpty)
              SliverToBoxAdapter(
                child: DinnaEmptyState(
                  icon: Icons.search_off,
                  title: 'Nenhum produto encontrado',
                  message: _noMatchMessage(viewModel.query, selected),
                  actionLabel: 'Limpar busca',
                  onAction: onClearSearch,
                  centered: false,
                ),
              ),
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
        );
      },
    );
  }
}

/// Busca sem resultado diz o que foi buscado e, com filtro, em qual categoria.
String _noMatchMessage(String query, String? category) {
  final where = category == null ? '' : ' em ${_categoryLabel(category)}';
  return 'Nenhum prato com “${query.trim()}”$where. Confira o nome ou limpe a busca.';
}

/// Campo de busca pelo nome. O botão de limpar só aparece com texto.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged, required this.onClear});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar pelo nome',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    icon: const Icon(Icons.close),
                    onPressed: onClear,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Erro e cardápio vazio rolam em tela baixa e ficam centralizados quando cabem.
///
/// A altura mínima é a viewport, então o bloco fica no centro quando sobra
/// espaço. Se o conteúdo é mais alto, a rolagem alcança a ação.
class _ScrollableStatus extends StatelessWidget {
  const _ScrollableStatus({required this.child, this.header});

  final Widget child;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [?header, child]),
          ),
        );
      },
    );
  }
}

Widget? _statusHeader(Widget? banner, Widget? recommendation) {
  if (banner == null && recommendation == null) return null;
  return Column(mainAxisSize: MainAxisSize.min, children: [?banner, ?recommendation]);
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

/// Onde o número da mesa cabe sem cortar o texto e sem tomar o cardápio.
class _HeaderLayout {
  const _HeaderLayout({
    required this.toolbarHeight,
    required this.badgeInToolbar,
    required this.badgeMaxWidth,
    required this.stackBadge,
  });

  final double toolbarHeight;
  final bool badgeInToolbar;
  final double badgeMaxWidth;
  final bool stackBadge;
}

/// Cabe ao lado da marca quando a altura medida cabe no limite. Se não cabe,
/// o selo desce para a largura da tela. Se ainda assim não sobra cardápio, o
/// número vai para a rolagem, inteiro.
_HeaderLayout _headerLayout(BuildContext context, String? table) {
  final scaler = MediaQuery.textScalerOf(context);
  final logoHeight = scaler.scale(24);
  final viewport = MediaQuery.sizeOf(context).height;
  final cap = math.max(kToolbarHeight, viewport * 0.4);
  final logoToolbar = math.max(kToolbarHeight, logoHeight + 8);

  if (table == null) {
    return _HeaderLayout(
      toolbarHeight: math.min(logoToolbar, cap),
      badgeInToolbar: false,
      badgeMaxWidth: 0,
      stackBadge: false,
    );
  }

  final besideWidth = _badgeMaxWidth(context);
  final besideToolbar = math.max(logoToolbar, _badgeOuterHeight(context, table, besideWidth) + 8);
  if (besideToolbar <= cap + 0.5) {
    return _HeaderLayout(
      toolbarHeight: besideToolbar,
      badgeInToolbar: true,
      badgeMaxWidth: besideWidth,
      stackBadge: false,
    );
  }

  final stackedWidth = math.max(48.0, MediaQuery.sizeOf(context).width - 32);
  final stackedToolbar = math.max(
    logoToolbar,
    logoHeight + 8 + _badgeOuterHeight(context, table, stackedWidth),
  );
  if (stackedToolbar <= cap + 0.5) {
    return _HeaderLayout(
      toolbarHeight: stackedToolbar,
      badgeInToolbar: true,
      badgeMaxWidth: stackedWidth,
      stackBadge: true,
    );
  }

  return _HeaderLayout(
    toolbarHeight: math.min(logoToolbar, cap),
    badgeInToolbar: false,
    badgeMaxWidth: stackedWidth,
    stackBadge: false,
  );
}

/// Rótulo na escala pedida. A forma curta só entra quando o texto inteiro
/// tomaria a faixa e esconderia o cardápio.
String _cartLabelThatFits(BuildContext context, String label, double maxWidth, String? table) {
  final scaler = MediaQuery.textScalerOf(context);
  final style = Theme.of(context).textTheme.labelLarge;
  final available = maxWidth.isFinite ? maxWidth : MediaQuery.sizeOf(context).width - 32;
  final width = math.max(1.0, available - 32);
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: scaler,
  )..layout(maxWidth: width);
  final header = _headerLayout(context, table);
  final budget = MediaQuery.sizeOf(context).height - header.toolbarHeight - 72;
  if (painter.height + 16 <= budget) return label;
  return 'Ver carrinho';
}

Widget? _recommendationButton(
  BuildContext context,
  String? table,
  void Function(BuildContext context, String? table)? open,
) {
  if (open == null) return null;
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: OutlinedButton(
      onPressed: () => open(context, table),
      child: const Text('Me ajuda a escolher', textAlign: TextAlign.center),
    ),
  );
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

/// Altura do selo na mesma largura em que ele é desenhado, com o texto inteiro.
double _badgeOuterHeight(BuildContext context, String table, double maxWidth) {
  final style = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
  final inner = math.max(1.0, maxWidth - 40);
  final painter = TextPainter(
    text: TextSpan(text: 'Mesa $table', style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: inner);
  return painter.height + 14;
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
