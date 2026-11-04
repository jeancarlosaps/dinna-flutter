import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/data_failure.dart';
import '../../core/domain/product.dart';
import '../../shared/widgets/dinna_banner.dart';
import '../../shared/widgets/dinna_empty_state.dart';
import '../restaurant/order_format.dart';
import 'product_detail_view_model.dart';
import 'product_image.dart';

///
Future<void> showProductDetail(
  BuildContext context, {
  required ProductDetailViewModel Function() createViewModel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxWidth: 480, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (_) => ProductDetailView(createViewModel: createViewModel),
  );
}

///
class ProductDetailView extends StatefulWidget {
  const ProductDetailView({super.key, required this.createViewModel});

  final ProductDetailViewModel Function() createViewModel;

  @override
  State<ProductDetailView> createState() => _ProductDetailViewState();
}

class _ProductDetailViewState extends State<ProductDetailView> {
  late final ProductDetailViewModel _viewModel;

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
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final product = _viewModel.product;
        return switch (_viewModel.status) {
          ProductDetailStatus.ready when product != null => _ProductDetailContent(product: product),
          ProductDetailStatus.failed => SingleChildScrollView(
            child: DinnaEmptyState(
              icon: _viewModel.failure == DataFailure.notFound ? Icons.search_off : Icons.wifi_off,
              title: _viewModel.failure == DataFailure.notFound
                  ? 'Produto não encontrado'
                  : 'Não foi possível carregar o produto',
              message: _viewModel.errorMessage ?? ProductDetailViewModel.unexpectedFailureMessage,
              actionLabel: 'Tentar de novo',
              onAction: _viewModel.load,
              centered: false,
            ),
          ),
          _ => const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
        };
      },
    );
  }
}

class _ProductDetailContent extends StatelessWidget {
  const _ProductDetailContent({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(height: 170, child: ProductImage(product: product)),
          ),
          const SizedBox(height: 14),
          Text(
            product.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          if (product.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              product.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                height: 1.4,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _IngredientsBox(ingredients: product.ingredients),
          const SizedBox(height: 12),
          Text(
            formatOrderTotal(product.priceCents),
            style: theme.textTheme.titleMedium?.copyWith(
              color: product.available ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
          if (!product.available) ...[
            const SizedBox(height: 12),
            const DinnaBanner(
              tone: DinnaBannerTone.warning,
              message: 'Este produto está esgotado no momento.',
            ),
          ],
        ],
      ),
    );
  }
}

/// Caixa "Ingredientes" do Figma. Lista vazia mantém a caixa e orienta quem
/// tem restrição alimentar a consultar o restaurante.
class _IngredientsBox extends StatelessWidget {
  const _IngredientsBox({required this.ingredients});

  /// Mensagem quando a API não informa os ingredientes.
  static const missingMessage =
      'Ingredientes não informados. Se você tem alergia ou restrição alimentar, '
      'consulte o restaurante antes de pedir.';

  final List<String> ingredients;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final missing = ingredients.isEmpty;

    // MergeSemantics: o leitor de tela lê título e conteúdo juntos.
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingredientes',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              missing ? missingMessage : ingredients.join(', '),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                color: missing ? colors.onSurfaceVariant : colors.onSurface,
                fontStyle: missing ? FontStyle.italic : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
