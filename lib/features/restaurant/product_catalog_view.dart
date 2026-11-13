import 'package:flutter/material.dart';

import '../../app/theme/dinna_colors.dart';
import '../../app/theme/dinna_layout.dart';
import '../../core/domain/product.dart';
import '../../shared/widgets/dinna_banner.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import 'order_format.dart';
import 'panel_brand_bar.dart';
import 'product_catalog_view_model.dart';
import 'restaurant_bottom_nav.dart';
import 'restaurant_rail.dart';

/// Lista e cadastro dos produtos do restaurante, na rota `/restaurant/menu`.
///
/// No celular a lista ocupa a tela e o formulário abre em página. No tablet
/// a lista usa a largura, com busca e filtros, e o formulário abre em painel.
class ProductCatalogView extends StatefulWidget {
  const ProductCatalogView({
    super.key,
    required this.createViewModel,
    this.onOpenOrders,
    this.onLeave,
  });

  final ProductCatalogViewModel Function() createViewModel;
  final void Function(BuildContext context)? onOpenOrders;
  final void Function(BuildContext context)? onLeave;

  @override
  State<ProductCatalogView> createState() => _ProductCatalogViewState();
}

class _ProductCatalogViewState extends State<ProductCatalogView> {
  late final ProductCatalogViewModel _viewModel = widget.createViewModel();
  final TextEditingController _search = TextEditingController();
  String? _category;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    _viewModel.load();
  }

  @override
  void dispose() {
    _search.removeListener(_onSearch);
    _search.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  Future<void> _openForm(Product? product) {
    final categories = {for (final item in _viewModel.products) item.category}.toList()..sort();
    final form = _ProductForm(viewModel: _viewModel, product: product, categories: categories);
    if (!DinnaLayout.isTablet(MediaQuery.sizeOf(context).width)) {
      return Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => form));
    }
    final height = MediaQuery.sizeOf(context).height;
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: SizedBox(width: 480, height: height * 0.9 > 760 ? 760 : height * 0.9, child: form),
      ),
    );
  }

  Future<void> _setAvailable(Product product, bool available) async {
    if (available == product.available || _viewModel.isSaving) return;
    final message = available
        ? await _viewModel.save(
            id: product.id,
            name: product.name,
            description: product.description,
            category: product.category,
            priceText: formatPriceInput(product.priceCents),
            imageText: product.imageUrl ?? '',
            ingredientsText: product.ingredients.join('\n'),
            available: true,
          )
        : await _viewModel.deactivate(product.id);
    if (message == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tablet = DinnaLayout.isTablet(constraints.maxWidth);
        return Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!tablet && widget.onLeave != null) PanelBrandBar(onLeave: widget.onLeave!),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (tablet && widget.onOpenOrders != null)
                      RestaurantRail(
                        section: RestaurantSection.products,
                        onOrders: () => widget.onOpenOrders!(context),
                        onLeave: widget.onLeave == null ? null : () => widget.onLeave!(context),
                      ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _viewModel,
                        builder: (context, _) => _CatalogBody(
                          viewModel: _viewModel,
                          search: _search,
                          category: _category,
                          onCategory: (value) => setState(() => _category = value),
                          onOpen: _openForm,
                          onAvailable: _setAvailable,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: !tablet && widget.onOpenOrders != null
              ? RestaurantBottomNav(
                  section: RestaurantSection.products,
                  onOrders: () => widget.onOpenOrders!(context),
                )
              : null,
        );
      },
    );
  }
}

class _CatalogBody extends StatelessWidget {
  const _CatalogBody({
    required this.viewModel,
    required this.search,
    required this.category,
    required this.onCategory,
    required this.onOpen,
    required this.onAvailable,
  });

  final ProductCatalogViewModel viewModel;
  final TextEditingController search;
  final String? category;
  final ValueChanged<String?> onCategory;
  final ValueChanged<Product?> onOpen;
  final Future<void> Function(Product product, bool available) onAvailable;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 960 ? 960.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, height: constraints.maxHeight, child: _content(context)),
        );
      },
    );
  }

  List<Product> get _visible {
    final query = search.text.trim().toLowerCase();
    return [
      for (final product in viewModel.products)
        if (category == null || product.category == category)
          if (query.isEmpty ||
              product.name.toLowerCase().contains(query) ||
              product.description.toLowerCase().contains(query))
            product,
    ];
  }

  Widget _content(BuildContext context) {
    if (viewModel.status == ProductCatalogStatus.loading && viewModel.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.status == ProductCatalogStatus.failed && viewModel.products.isEmpty) {
      return _ScrollableFill(
        child: DinnaEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Não foi possível carregar',
          message: viewModel.errorMessage ?? ProductCatalogViewModel.loadError,
          actionLabel: 'Tentar novamente',
          onAction: viewModel.load,
        ),
      );
    }
    if (viewModel.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CatalogToolbar(search: search, onCreate: () => onOpen(null)),
          const Expanded(
            child: _ScrollableFill(
              child: DinnaEmptyState(
                icon: Icons.restaurant_menu_outlined,
                title: 'Nenhum produto cadastrado',
                message: 'Cadastre o primeiro item do cardápio.',
              ),
            ),
          ),
        ],
      );
    }

    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CatalogToolbar(search: search, onCreate: () => onOpen(null)),
        _CategoryFilters(products: viewModel.products, selected: category, onSelected: onCategory),
        if (visible.isEmpty)
          const Expanded(
            child: _ScrollableFill(
              child: DinnaEmptyState(
                icon: Icons.search_off_outlined,
                title: 'Nenhum produto encontrado',
                message: 'Tente outro nome ou outra categoria.',
              ),
            ),
          )
        else
          Expanded(child: _grouped(visible)),
      ],
    );
  }

  Widget _grouped(List<Product> visible) {
    final groups = <String, List<Product>>{};
    for (final product in visible) {
      groups.putIfAbsent(product.category, () => []).add(product);
    }
    final products = [for (final name in groups.keys) ...groups[name]!];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 24),
      itemCount: products.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductRow(
          product: product,
          saving: viewModel.isSaving,
          onOpen: () => onOpen(product),
          onAvailable: (value) => onAvailable(product, value),
        );
      },
    );
  }
}

class _CatalogToolbar extends StatelessWidget {
  const _CatalogToolbar({required this.search, required this.onCreate});

  final TextEditingController search;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = Text(
      'Produtos',
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final button = TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onCreate,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Novo produto'),
    );
    final searchField = TextField(
      controller: search,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Buscar',
        prefixIcon: Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
        isDense: true,
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    button,
                  ],
                ),
                const SizedBox(height: 12),
                searchField,
              ],
            );
          }
          return Row(
            children: [
              title,
              const Spacer(),
              SizedBox(width: 280, child: searchField),
              const SizedBox(width: 8),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({
    required this.products,
    required this.selected,
    required this.onSelected,
  });

  final List<Product> products;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final categories = products.map((product) => product.category).toSet().toList()..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          _FilterLabel(label: 'Todos', selected: selected == null, onTap: () => onSelected(null)),
          for (final name in categories)
            _FilterLabel(
              label: _categoryLabel(name),
              selected: selected == name,
              onTap: () => onSelected(name),
            ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.saving,
    required this.onOpen,
    required this.onAvailable,
  });

  final Product product;
  final bool saving;
  final VoidCallback onOpen;
  final ValueChanged<bool> onAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = product.available
        ? formatOrderTotal(product.priceCents)
        : '${formatOrderTotal(product.priceCents)} · Esgotado';
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _ProductThumb(product: product),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Switch(
              value: product.available,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) return DinnaColors.muted;
                return states.contains(WidgetState.selected)
                    ? DinnaColors.brown
                    : DinnaColors.white;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? DinnaColors.line
                    : const Color(0xFFE7DED6);
              }),
              trackOutlineColor: WidgetStateProperty.all(DinnaColors.line),
              onChanged: saving ? null : onAvailable,
            ),
          ],
        ),
      ),
    );
  }
}

String _categoryLabel(String slug) {
  final cleaned = slug.trim();
  if (cleaned.isEmpty) return cleaned;
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    const placeholderColor = Color(0xFFF3EBE4);
    final placeholder = const ColoredBox(
      color: placeholderColor,
      child: Icon(Icons.image_outlined, size: 16, color: DinnaColors.muted),
    );
    final url = product.imageUrl;
    Widget image = placeholder;
    if (url != null && url.isNotEmpty) {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      );
    }
    if (!product.available) {
      image = Opacity(opacity: 0.45, child: image);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 40, height: 40, child: image),
    );
  }
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({required this.viewModel, required this.product, required this.categories});

  final ProductCatalogViewModel viewModel;
  final Product? product;
  final List<String> categories;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _price;
  late final TextEditingController _image;
  late final TextEditingController _ingredients;
  late final FocusNode _imageFocus;
  late bool _available;
  String? _error;

  bool get _dialog => DinnaLayout.isTablet(MediaQuery.sizeOf(context).width);

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _category = TextEditingController(text: product?.category ?? '');
    _price = TextEditingController(
      text: product == null ? '' : formatPriceInput(product.priceCents),
    );
    _image = TextEditingController(text: product?.imageUrl ?? '');
    _ingredients = TextEditingController(text: product?.ingredients.join('\n') ?? '');
    _imageFocus = FocusNode();
    _available = product?.available ?? true;
    _image.addListener(_refresh);
    _category.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _image.removeListener(_refresh);
    _category.removeListener(_refresh);
    _name.dispose();
    _description.dispose();
    _category.dispose();
    _price.dispose();
    _image.dispose();
    _ingredients.dispose();
    _imageFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final message = await widget.viewModel.save(
      id: widget.product?.id,
      name: _name.text,
      description: _description.text,
      category: _category.text,
      priceText: _price.text,
      imageText: _image.text,
      ingredientsText: _ingredients.text,
      available: _available,
    );
    if (!mounted) return;
    if (message == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _error = message);
  }

  Future<void> _deactivate() async {
    final product = widget.product;
    if (product == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desativar produto'),
        content: Text('${product.name} sai do cardápio do cliente e continua nesta lista.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final message = await widget.viewModel.deactivate(product.id);
    if (!mounted) return;
    if (message == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.product != null;
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final saving = widget.viewModel.isSaving;
        final fields = _fields(context, saving, editing);
        final actions = _actions(context, saving, editing);
        if (!_dialog) {
          return Scaffold(
            appBar: AppBar(title: Text(editing ? 'Editar produto' : 'Cadastrar produto')),
            body: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [...fields, ...actions],
                ),
              ),
            ),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.surfaceContainerLowest,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        editing ? 'Editar produto' : 'Novo produto',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  children: fields,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: actions,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _fields(BuildContext context, bool saving, bool editing) {
    final scheme = Theme.of(context).colorScheme;
    final imageText = _image.text.trim();
    final imageUri = Uri.tryParse(imageText);
    final hasImage = imageUri != null && imageUri.hasScheme;
    return [
      if (_error != null) ...[
        DinnaBanner(tone: DinnaBannerTone.error, message: _error!),
        const SizedBox(height: 12),
      ],
      GestureDetector(
        onTap: () => _imageFocus.requestFocus(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              height: 112,
              width: double.infinity,
              child: hasImage
                  ? Image.network(
                      imageText,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _imagePlaceholder(editing),
                    )
                  : _imagePlaceholder(editing),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _name,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Nome'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _description,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Descrição'),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preço',
                hintText: '32,90',
                prefixText: 'R\$ ',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _category,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Categoria', hintText: 'burgers'),
            ),
          ),
        ],
      ),
      if (widget.categories.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in widget.categories)
              ChoiceChip(
                label: Text(name),
                selected: _category.text.trim() == name,
                onSelected: saving
                    ? null
                    : (_) {
                        _category.text = name;
                        _category.selection = TextSelection.collapsed(offset: name.length);
                      },
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _image,
        focusNode: _imageFocus,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'Link da imagem'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _ingredients,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'Ingredientes',
          hintText: 'Um por linha',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Disponível no cardápio'),
        subtitle: const Text('Desligue quando acabar: some do app na hora.'),
        value: _available,
        onChanged: saving ? null : (value) => setState(() => _available = value),
      ),
    ];
  }

  List<Widget> _actions(BuildContext context, bool saving, bool editing) {
    return [
      if (editing && widget.product!.available)
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: saving ? null : _deactivate,
          child: const Text('Desativar'),
        ),
      if (_dialog)
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: saving ? null : _save,
        child: Text(saving ? 'Salvando…' : (editing ? 'Salvar alterações' : 'Cadastrar produto')),
      ),
    ];
  }

  Widget _imagePlaceholder(bool editing) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        editing ? 'Trocar foto' : 'Adicionar foto',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
      ),
    );
  }
}

class _ScrollableFill extends StatelessWidget {
  const _ScrollableFill({required this.child});

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
