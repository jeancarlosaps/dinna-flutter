import 'package:flutter/material.dart';

import '../../app/theme/dinna_colors.dart';

/// Tom visual do [DinnaBanner].
enum DinnaBannerTone { info, warning, error }

/// Caixa de aviso com ícone, título opcional e mensagem.
class DinnaBanner extends StatelessWidget {
  const DinnaBanner({super.key, required this.tone, required this.message, this.title});

  final DinnaBannerTone tone;
  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (tone) {
      DinnaBannerTone.info => (DinnaColors.sageSoft, DinnaColors.sage, Icons.info_outline),
      DinnaBannerTone.warning => (
        DinnaColors.amberSoft,
        DinnaColors.amber,
        Icons.warning_amber_rounded,
      ),
      DinnaBannerTone.error => (DinnaColors.terracottaSoft, DinnaColors.error, Icons.error_outline),
    };
    final textStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurface);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!, style: textStyle?.copyWith(fontWeight: FontWeight.w700)),
                Text(message, style: textStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
