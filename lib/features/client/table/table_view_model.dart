import 'package:flutter/foundation.dart';

/// Valida o número da mesa digitado na entrada do cliente.
class TableViewModel extends ChangeNotifier {
  String? _errorMessage;

  /// Mensagem para mostrar abaixo do campo. Nula quando não há erro.
  String? get errorMessage => _errorMessage;

  /// Devolve a mesa normalizada (ex.: "12") se for válida; senão guarda o erro e devolve null.
  String? submit(String input) {
    final text = input.trim();
    final number = int.tryParse(text);

    if (text.isEmpty) {
      _errorMessage = 'Informe o número da mesa.';
    } else if (number == null || number <= 0) {
      _errorMessage = 'Número de mesa inválido.';
    } else {
      _errorMessage = null;
    }

    notifyListeners();
    return _errorMessage == null ? '$number' : null;
  }
}
