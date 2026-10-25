import 'package:flutter/material.dart';

/// Página mínima para validar o roteamento enquanto a View da rota não existe.
///
/// A story da tela substitui este widget no `switch` do router. O nome da rota permanece.
class RoutePlaceholder extends StatelessWidget {
  const RoutePlaceholder({super.key, required this.routeName});

  final String routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(routeName)),
      body: const Center(child: Text('Tela ainda não implementada.')),
    );
  }
}

/// Resposta para um nome de rota fora do mapa.
class UnknownRouteView extends StatelessWidget {
  const UnknownRouteView({super.key, this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    final name = routeName;
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Página não encontrada'),
            if (name != null) ...[
              const SizedBox(height: 8),
              Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
