import 'package:flutter/material.dart';

class TableView extends StatelessWidget {
  const TableView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight, maxWidth: 440),
                  child: IntrinsicHeight(
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
                                height: 1.0,
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
                          const SizedBox(height: 4),
                          Container(
                            width: 20,
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Pedido à mesa, do seu jeito.',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 40),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('Qual é a sua mesa?', style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                    'O número fica na plaquinha em cima da mesa.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Semantics(
                                    label: 'Número da mesa',
                                    child: TextField(
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        prefixIcon: Padding(
                                          padding: EdgeInsets.only(left: 16, right: 8),
                                          child: Text('Mesa'),
                                        ),
                                        prefixIconConstraints: BoxConstraints(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(onPressed: () {}, child: const Text('Ver cardápio')),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Sem cadastro. Você pede e acompanha tudo por aqui.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Trabalha no restaurante?',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                TextButton(onPressed: () {}, child: const Text('Acessar o painel')),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
