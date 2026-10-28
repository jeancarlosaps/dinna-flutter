import 'dart:async';

import 'package:dinna/core/domain/data_failure.dart';
import 'package:dinna/features/home/api_status_repository.dart';
import 'package:dinna/features/home/home_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_status_repository.dart';

void main() {
  test('começa sem verificação', () {
    final viewModel = HomeViewModel(
      FakeApiStatusRepository(() async => const ApiAvailability.online()),
    );

    expect(viewModel.status, ApiStatus.unknown);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
  });

  test('fica em checking até a resposta e online quando a API está ok', () async {
    final completer = Completer<ApiAvailability>();
    final viewModel = HomeViewModel(FakeApiStatusRepository(() => completer.future));
    final states = <ApiStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    final pending = viewModel.checkApi();

    expect(viewModel.status, ApiStatus.checking);
    expect(viewModel.errorMessage, isNull);

    completer.complete(const ApiAvailability.online());
    await pending;

    expect(viewModel.status, ApiStatus.online);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
    expect(states, [ApiStatus.checking, ApiStatus.online]);
  });

  test('fica offline e expõe a mensagem quando a verificação falha', () async {
    final viewModel = HomeViewModel(
      FakeApiStatusRepository(
        () async => const ApiAvailability.offline('Não foi possível conectar à API'),
      ),
    );
    final states = <ApiStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    await viewModel.checkApi();

    expect(states, [ApiStatus.checking, ApiStatus.offline]);
    expect(viewModel.errorMessage, 'Não foi possível conectar à API');
    expect(viewModel.failure, DataFailure.unavailable);
  });

  test('guarda o tipo da falha e deixa o detalhe técnico fora da mensagem', () async {
    final viewModel = HomeViewModel(
      FakeApiStatusRepository(
        () async => const ApiAvailability.offline(
          'Pedido não encontrado',
          failure: DataFailure.notFound,
          detail: 'Connection refused',
        ),
      ),
    );

    await viewModel.checkApi();

    expect(viewModel.status, ApiStatus.offline);
    expect(viewModel.errorMessage, 'Pedido não encontrado');
    expect(viewModel.errorMessage, isNot(contains('Connection refused')));
    expect(viewModel.failure, DataFailure.notFound);
  });

  test('não notifica de novo se a tela for descartada durante a verificação', () async {
    final completer = Completer<ApiAvailability>();
    final viewModel = HomeViewModel(FakeApiStatusRepository(() => completer.future));
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.checkApi();
    expect(notifications, 1);

    viewModel.dispose();
    completer.complete(const ApiAvailability.online());
    await pending;

    expect(notifications, 1);
    expect(viewModel.status, ApiStatus.checking);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
  });

  test('checkApi depois do dispose não consulta nem notifica', () async {
    var calls = 0;
    final viewModel = HomeViewModel(
      FakeApiStatusRepository(() async {
        calls++;
        return const ApiAvailability.online();
      }),
    );

    viewModel.dispose();
    await viewModel.checkApi();

    expect(calls, 0);
    expect(viewModel.status, ApiStatus.unknown);
    expect(viewModel.errorMessage, isNull);
    expect(viewModel.failure, isNull);
  });

  test('exceção inesperada sai de checking e fica offline sem detalhe interno', () async {
    const detalheInterno = 'falha interna do repository';
    final viewModel = HomeViewModel(
      FakeApiStatusRepository(() async => throw StateError(detalheInterno)),
    );
    final states = <ApiStatus>[];
    viewModel.addListener(() => states.add(viewModel.status));

    await viewModel.checkApi();

    expect(states, [ApiStatus.checking, ApiStatus.offline]);
    expect(viewModel.errorMessage, HomeViewModel.unexpectedFailureMessage);
    expect(viewModel.errorMessage, isNot(contains(detalheInterno)));
    expect(viewModel.failure, DataFailure.unavailable);
  });

  test('exceção inesperada depois do dispose termina sem atualizar nem notificar', () async {
    final completer = Completer<ApiAvailability>();
    final viewModel = HomeViewModel(FakeApiStatusRepository(() => completer.future));
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    final pending = viewModel.checkApi();
    expect(viewModel.status, ApiStatus.checking);
    expect(notifications, 1);

    viewModel.dispose();
    completer.completeError(StateError('falha interna do repository'));
    await pending;

    expect(notifications, 1);
    expect(viewModel.status, ApiStatus.checking);
    expect(viewModel.errorMessage, isNull);
  });
}
