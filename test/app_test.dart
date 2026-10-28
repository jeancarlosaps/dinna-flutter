import 'package:dinna/app/app.dart';
import 'package:dinna/app/theme/dinna_colors.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/menu/product_repository.dart';
import 'package:dinna/features/restaurant/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'features/home/fake_api_status_repository.dart';
import 'features/menu/fake_product_repository.dart';
import 'features/restaurant/fake_order_repository.dart';

void main() {
  testWidgets('inicia na home com a identidade Dinna aplicada', (tester) async {
    await tester.pumpWidget(
      DinnaApp(
        apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
        orderRepository: FakeOrderRepository(() async => OrderList.ready(const [])),
        productRepository: FakeProductRepository(() async => ProductList.ready(const [])),
        pollDelay: pendingPollDelay,
      ),
    );

    expect(find.text('dinna'), findsOneWidget);
    expect(find.text('Pedido à mesa, do seu jeito.'), findsOneWidget);

    final theme = Theme.of(tester.element(find.text('dinna')));
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, DinnaColors.terracotta);
    expect(theme.colorScheme.surface, DinnaColors.cream);
  });

  testWidgets('verifica a API pelo fluxo View → ViewModel → Repository', (tester) async {
    await tester.pumpWidget(
      DinnaApp(
        apiStatusRepository: FakeApiStatusRepository(() async => const ApiAvailability.online()),
        orderRepository: FakeOrderRepository(() async => OrderList.ready(const [])),
        productRepository: FakeProductRepository(() async => ProductList.ready(const [])),
        pollDelay: pendingPollDelay,
      ),
    );

    expect(find.text('API não verificada'), findsOneWidget);

    await tester.tap(find.text('Verificar conexão com a API'));
    await tester.pump();

    expect(find.text('API online'), findsOneWidget);
  });
}
