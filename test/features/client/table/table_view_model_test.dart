import 'package:dinna/features/client/table/table_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mesa vazia mostra erro', () {
    final viewModel = TableViewModel();

    expect(viewModel.submit('  '), isNull);
    expect(viewModel.errorMessage, 'Informe o número da mesa.');
  });

  test('mesa zero ou com letras é inválida', () {
    final viewModel = TableViewModel();

    expect(viewModel.submit('0'), isNull);
    expect(viewModel.errorMessage, 'Número de mesa inválido.');

    expect(viewModel.submit('abc'), isNull);
    expect(viewModel.errorMessage, 'Número de mesa inválido.');
  });

  test('mesa válida devolve o número normalizado e limpa o erro', () {
    final viewModel = TableViewModel()..submit('');

    expect(viewModel.submit(' 012 '), '12');
    expect(viewModel.errorMessage, isNull);
  });
}
