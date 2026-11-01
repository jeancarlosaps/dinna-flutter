import 'package:flutter/material.dart';

/// Estado vazio, de erro ou sem resultado: ícone, título, mensagem e ação opcional.
class DinnaEmptyState extends StatelessWidget {
  const DinnaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.centered = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Falso quando o pai já rola e a altura máxima é livre.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: colors.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: colors.primary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
    if (!centered) return content;
    return Center(child: content);
  }
}
