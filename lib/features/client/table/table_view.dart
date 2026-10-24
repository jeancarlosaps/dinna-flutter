import 'package:flutter/material.dart';

class TableView extends StatelessWidget {
  const TableView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 50),
              Text.rich(
                TextSpan(
                  text: 'dinna',
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -2,
                    color: theme.colorScheme.onSurface,
                  ),
                  children: [
                    TextSpan(
                      text: '.',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
              Text(
                'Pedido à mesa, do seu jeito.',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
