import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/dinna_theme.dart';
import '../../../shared/widgets/dinna_logo.dart';
import 'table_view_model.dart';

class TableView extends StatefulWidget {
  const TableView({super.key});

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  final _tableController = TextEditingController();
  final _viewModel = TableViewModel();

  @override
  void dispose() {
    _tableController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _submit() {
    final table = _viewModel.submit(_tableController.text);
    if (table == null) return;
    Navigator.of(context).pushNamed(AppRoutes.menu, arguments: table);
  }

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
                          const DinnaLogo(),
                          const SizedBox(height: 4),
                          Container(
                            width: 20,
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pedido à mesa, do seu jeito.',
                            style: DinnaTheme.taglineStyle.copyWith(
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
                                  ListenableBuilder(
                                    listenable: _viewModel,
                                    builder: (context, _) => Semantics(
                                      label: 'Número da mesa',
                                      child: TextField(
                                        controller: _tableController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        textInputAction: TextInputAction.go,
                                        onSubmitted: (_) => _submit(),
                                        decoration: InputDecoration(
                                          prefixIcon: const Padding(
                                            padding: EdgeInsets.only(left: 16, right: 8),
                                            child: Text('Mesa'),
                                          ),
                                          prefixIconConstraints: const BoxConstraints(),
                                          errorText: _viewModel.errorMessage,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: _submit,
                                    child: const Text('Ver cardápio'),
                                  ),
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
