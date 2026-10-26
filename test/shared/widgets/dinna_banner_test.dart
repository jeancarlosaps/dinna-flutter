import 'package:dinna/shared/widgets/dinna_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mostra título e mensagem', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DinnaBanner(
            tone: DinnaBannerTone.warning,
            title: 'Tem alergia?',
            message: 'Confirme os ingredientes com a equipe.',
          ),
        ),
      ),
    );

    expect(find.text('Tem alergia?'), findsOneWidget);
    expect(find.text('Confirme os ingredientes com a equipe.'), findsOneWidget);
  });

  testWidgets('sem título mostra só a mensagem', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DinnaBanner(
            tone: DinnaBannerTone.info,
            message: 'O pagamento é feito com a equipe.',
          ),
        ),
      ),
    );
    expect(find.text('O pagamento é feito com a equipe.'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });
}
