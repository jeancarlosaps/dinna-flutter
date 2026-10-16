import 'package:dinna/core/network/api_exception.dart';
import 'package:dinna/features/home/home_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_status_repository.dart';

void main() {
  test('começa sem verificação', () {
    final viewModel = HomeViewModel(FakeApiStatusRepository(() async => true));

    expect(viewModel.status, ApiStatus.unknown);
    expect(viewModel.errorMessage, isNull);
  });

  test('fica online quando a API responde ok', () async {
    final viewModel = HomeViewModel(FakeApiStatusRepository(() async => true));
    final states = <ApiStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    await viewModel.checkApi();

    expect(states, [ApiStatus.checking, ApiStatus.online]);
  });

  test('fica offline e expõe a mensagem quando a API falha', () async {
    final viewModel = HomeViewModel(
      FakeApiStatusRepository(
        () async => throw const ApiException('Não foi possível conectar à API'),
      ),
    );

    await viewModel.checkApi();

    expect(viewModel.status, ApiStatus.offline);
    expect(viewModel.errorMessage, 'Não foi possível conectar à API');
  });
}
