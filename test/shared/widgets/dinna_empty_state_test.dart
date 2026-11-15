import 'package:dinna/shared/widgets/dinna_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sem ação não mostra botão', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DinnaEmptyState(
            icon: Icons.receipt_long,
            title: 'Nenhum pedido agora',
            message: 'Quando uma mesa enviar um pedido, ele aparece aqui.',
          ),
        ),
      ),
    );

    expect(find.text('Nenhum pedido agora'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('tocar no botão chama onAction', (tester) async {
    var tocou = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DinnaEmptyState(
            icon: Icons.shopping_cart_outlined,
            title: 'Seu carrinho está vazio',
            message: 'Escolha os pratos no cardápio.',
            actionLabel: 'Ver cardápio',
            onAction: () => tocou = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ver cardápio'));

    expect(tocou, isTrue);
  });
}
