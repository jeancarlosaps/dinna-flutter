import 'package:flutter/material.dart';

import '../../app/theme/dinna_colors.dart';
import '../../core/domain/product.dart';

/// Foto do produto, ou o degradê do Figma quando não há foto.
///
/// Produto esgotado sai em cinza. Usada no card do cardápio e no detalhe.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
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
    final image = imageUrl == null
        ? placeholder
        : Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);

    if (product.available) return image;
    return Opacity(
      opacity: 0.55,
      child: ColorFiltered(colorFilter: _grayscale, child: image),
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
