import 'dart:async';

import 'package:dinna/app/theme/dinna_theme.dart';
import 'package:dinna/features/recommendation/recommendation.dart';
import 'package:dinna/features/recommendation/recommendation_preferences.dart';
import 'package:dinna/features/recommendation/recommendation_repository.dart';
import 'package:dinna/features/recommendation/recommendation_view.dart';
import 'package:dinna/features/recommendation/recommendation_view_model.dart';
import 'package:dinna/shared/widgets/dinna_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_recommendation_repository.dart';

const _allergy = 'Tem alergia? Confirme os ingredientes com a equipe antes de pedir.';

void main() {
  testWidgets('mostra as perguntas, a alergia e o botão desabilitado', (tester) async {
    await _pump(
      tester,
      RecommendationViewModel(FakeRecommendationRepository((_) async => _answered())),
    );

    expect(find.text('Me ajuda a escolher'), findsOneWidget);
    expect(find.text(_allergy), findsOneWidget);
    await _see(tester, 'Quanto pretende gastar?');
    await _see(tester, 'Qual é o tamanho da sua fome?');
    await _see(tester, 'Qual proteína prefere?');
    await _see(tester, 'Que tipo de refeição deseja?');
    await _see(tester, 'Prefere salgado ou doce?');
    await _see(tester, 'Possui alguma restrição alimentar?');
    await _see(tester, 'Opcional. Pode marcar várias.');
    for (final restriction in DietaryRestriction.values) {
      await _see(tester, restriction.label);
    }
    await _scrollToSubmit(tester);
    expect(_submitButton(tester).onPressed, isNull);
  });

  testWidgets('seleção única e restrições múltiplas habilitam o botão', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await _pump(
        tester,
        RecommendationViewModel(FakeRecommendationRepository((_) async => _answered())),
      );

      await _answerForm(tester);
      await _tapLabel(tester, DietaryRestriction.noOnion.label);
      await _tapLabel(tester, DietaryRestriction.noGluten.label);
      await _scrollToSubmit(tester);

      expect(_submitButton(tester).onPressed, isNotNull);
      final onion = find.widgetWithText(CheckboxListTile, 'Sem cebola');
      final gluten = find.widgetWithText(CheckboxListTile, 'Sem glúten');
      final chicken = find.widgetWithText(RadioListTile<MealProtein>, 'Frango');
      await tester.scrollUntilVisible(onion, -400);
      expect(
        tester.getSemantics(onion),
        isSemantics(label: 'Sem cebola', hasCheckedState: true, isChecked: true),
      );
      await tester.scrollUntilVisible(gluten, 200);
      expect(
        tester.getSemantics(gluten),
        isSemantics(label: 'Sem glúten', hasCheckedState: true, isChecked: true),
      );
      await tester.scrollUntilVisible(chicken, -400);
      expect(
        tester.getSemantics(chicken),
        isSemantics(
          label: 'Frango',
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
    } finally {
      handle.dispose();
    }
  });

  testWidgets('contradição fica visível e não apaga a escolha', (tester) async {
    await _pump(
      tester,
      RecommendationViewModel(FakeRecommendationRepository((_) async => _answered())),
    );
    await _answerForm(tester, protein: 'Peixe');
    await _tapLabel(tester, 'Sem frutos do mar');
    expect(find.text(RecommendationViewModel.fishAndSeafoodMessage), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Peixe'), -400);
    expect(find.text('Peixe'), findsWidgets);
    await _scrollToSubmit(tester);
    expect(_submitButton(tester).onPressed, isNull);

    await _tapLabel(tester, 'Sem frutos do mar');
    expect(find.text(RecommendationViewModel.fishAndSeafoodMessage), findsNothing);
    await _scrollToSubmit(tester);
    expect(_submitButton(tester).onPressed, isNotNull);
    await tester.scrollUntilVisible(find.text('Peixe'), -400);
    expect(find.text('Peixe'), findsWidgets);
  });

  testWidgets('loading impede outro envio e o resultado lista só o motivo', (tester) async {
    final pending = Completer<RecommendationAttempt>();
    var calls = 0;
    final viewModel = RecommendationViewModel(
      FakeRecommendationRepository((_) {
        calls += 1;
        return calls == 1
            ? pending.future
            : Future<RecommendationAttempt>.value(_answered(reason: 'Frango, Salgado'));
      }),
    );
    await _pump(tester, viewModel);
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pump();

    expect(find.text('Preparando uma sugestão…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Quanto pretende gastar?'), findsNothing);
    expect(calls, 1);

    pending.complete(_answered());
    await tester.pumpAndSettle();

    expect(find.text('Carne, Salgado'), findsOneWidget);
    expect(find.text(_allergy), findsOneWidget);
    expect(find.text('p3'), findsNothing);
    expect(find.text('A Dinna não respondeu agora'), findsNothing);
    expect(find.text('Ver cardápio completo'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Quanto pretende gastar?'), findsOneWidget);
    await _scrollToSubmit(tester);
    expect(_submitButton(tester).onPressed, isNotNull);
    expect(viewModel.budget, MealBudget.upTo20);
  });

  testWidgets('fallback mostra a faixa e a nova tentativa', (tester) async {
    var calls = 0;
    final viewModel = RecommendationViewModel(
      FakeRecommendationRepository((_) async {
        calls += 1;
        return RecommendationAttempt.ready(
          Recommendation(
            provider: RecommendationProvider.unavailable,
            outcome: RecommendationOutcome.suggestions,
            products: [RecommendationSuggestion(productId: 'p2', reason: 'Carne, Salgado')],
          ),
        );
      }),
    );
    await _pump(tester, viewModel);
    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();

    expect(find.byType(DinnaBanner), findsWidgets);
    expect(find.text('A Dinna não respondeu agora'), findsOneWidget);
    expect(
      find.text(
        'Seu pedido continua funcionando normalmente. Separei pratos do cardápio que batem com os seus filtros.',
      ),
      findsOneWidget,
    );
    expect(find.text('Carne, Salgado'), findsOneWidget);
    expect(find.text(_allergy), findsOneWidget);

    await _tapLabel(tester, 'Tentar a Dinna de novo');
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(viewModel.phase, RecommendationPhase.fallback);
  });

  testWidgets('vazio compatível, cardápio vazio e erro com nova tentativa', (tester) async {
    final outcomes = <RecommendationAttempt>[
      RecommendationAttempt.ready(
        Recommendation(
          provider: RecommendationProvider.notCalled,
          outcome: RecommendationOutcome.noCompatibleProducts,
          products: const [],
        ),
      ),
      RecommendationAttempt.ready(
        Recommendation(
          provider: RecommendationProvider.notCalled,
          outcome: RecommendationOutcome.emptyCatalog,
          products: const [],
        ),
      ),
      const RecommendationAttempt.failed(
        RecommendationFailure.unavailable,
        title: 'Não foi possível pedir uma sugestão',
        message: 'O cardápio, o carrinho e o pedido continuam disponíveis.',
      ),
      _answered(reason: 'Frango, Salgado'),
    ];
    var index = 0;
    final viewModel = RecommendationViewModel(
      FakeRecommendationRepository((_) async => outcomes[index++]),
    );
    await _pump(tester, viewModel);
    await _answerForm(tester);

    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    expect(find.text('Nenhum prato compatível'), findsOneWidget);
    expect(
      find.text(
        'Não há, no cardápio disponível, um prato que respeite essas respostas sem completar informação que o cadastro não tem.',
      ),
      findsOneWidget,
    );
    expect(find.text(_allergy), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    expect(find.text('Cardápio vazio'), findsOneWidget);
    expect(
      find.text('O restaurante ainda não tem pratos disponíveis para sugerir.'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível pedir uma sugestão'), findsOneWidget);
    expect(find.text('O cardápio, o carrinho e o pedido continuam disponíveis.'), findsOneWidget);
    expect(find.text('pode ter sido registrado'), findsNothing);

    await _tapLabel(tester, 'Tentar de novo');
    await tester.pumpAndSettle();
    expect(find.text('Frango, Salgado'), findsOneWidget);
    expect(viewModel.phase, RecommendationPhase.suggestions);
  });

  testWidgets('ver cardápio completo volta para a mesma rota', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: DinnaTheme.light(), home: const _MenuHost()));

    await tester.tap(find.text('abrir recomendação'));
    await tester.pumpAndSettle();
    expect(find.text('Quanto pretende gastar?'), findsOneWidget);

    await _answerForm(tester);
    await _tapLabel(tester, 'Me sugere um prato');
    await tester.pumpAndSettle();
    await _tapLabel(tester, 'Ver cardápio completo');
    await tester.pumpAndSettle();

    expect(find.text('cardápio mesa 12'), findsOneWidget);
    expect(find.text('Me sugere um prato'), findsNothing);
  });

  testWidgets('texto ampliado rola sem overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: DinnaTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: RecommendationView(
          createViewModel: () =>
              RecommendationViewModel(FakeRecommendationRepository((_) async => _answered())),
          onShowMenu: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _see(tester, 'Sem frutos do mar');
    await _see(tester, 'Me sugere um prato');
    final budget = find.widgetWithText(RadioListTile<MealBudget>, 'Até R\$ 20');
    await tester.scrollUntilVisible(budget, -400);
    final tile = tester.renderObject<RenderBox>(budget);
    expect(tile.size.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, RecommendationViewModel viewModel) {
  return tester.pumpWidget(
    MaterialApp(
      theme: DinnaTheme.light(),
      home: RecommendationView(createViewModel: () => viewModel, onShowMenu: (_) {}),
    ),
  );
}

Future<void> _see(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 400);
  expect(find.text(text), findsWidgets);
}

Future<void> _tapLabel(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.scrollUntilVisible(finder, 400);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _answerForm(WidgetTester tester, {String protein = 'Frango'}) async {
  await _tapLabel(tester, 'Até R\$ 20');
  await _tapLabel(tester, 'Normal');
  await _tapLabel(tester, protein);
  await _tapLabel(tester, 'Equilibrado');
  await _tapLabel(tester, 'Salgado');
}

FilledButton _submitButton(WidgetTester tester) {
  final finder = find.widgetWithText(FilledButton, 'Me sugere um prato');
  return tester.widget<FilledButton>(finder);
}

Future<void> _scrollToSubmit(WidgetTester tester) {
  return tester.scrollUntilVisible(find.widgetWithText(FilledButton, 'Me sugere um prato'), 400);
}

RecommendationAttempt _answered({String reason = 'Carne, Salgado'}) {
  return RecommendationAttempt.ready(
    Recommendation(
      provider: RecommendationProvider.answered,
      outcome: RecommendationOutcome.suggestions,
      products: [RecommendationSuggestion(productId: 'p3', reason: reason)],
    ),
  );
}

class _MenuHost extends StatefulWidget {
  const _MenuHost();

  @override
  State<_MenuHost> createState() => _MenuHostState();
}

class _MenuHostState extends State<_MenuHost> {
  var opened = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(opened ? 'cardápio mesa 12' : 'cardápio ainda fechado'),
            TextButton(
              onPressed: () {
                setState(() => opened = true);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/recommendation', arguments: '12'),
                    builder: (routeContext) => RecommendationView(
                      createViewModel: () => RecommendationViewModel(
                        FakeRecommendationRepository((_) async => _answered()),
                        table: '12',
                      ),
                      onShowMenu: (menuContext) => Navigator.of(menuContext).pop(),
                    ),
                  ),
                );
              },
              child: const Text('abrir recomendação'),
            ),
          ],
        ),
      ),
    );
  }
}
