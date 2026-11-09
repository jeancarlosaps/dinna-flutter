import 'package:flutter/foundation.dart';

/// Valida o número da mesa digitado na entrada do cliente.
class TableViewModel extends ChangeNotifier {
  /// Dígitos aceitos no campo: mesas de 1 a [maxTable].
  static const maxDigits = 3;
  static const maxTable = 999;

  static final _digitsOnly = RegExp(r'^\d+$');
  String? _errorMessage;

  /// Mensagem para mostrar abaixo do campo. Nula quando não há erro.
  String? get errorMessage => _errorMessage;

  /// Devolve a mesa normalizada (ex.: "12") se for válida; senão guarda o erro e devolve null.
  String? submit(String input) {
    final text = input.trim();
    // tryParse: um número grande demais para `int` vira inválido, sem exceção.
    final number = _digitsOnly.hasMatch(text) ? int.tryParse(text) : null;

    if (text.isEmpty) {
      _errorMessage = 'Informe o número da mesa.';
    } else if (number == null || number <= 0 || number > maxTable) {
      _errorMessage = 'Número de mesa inválido.';
    } else {
      _errorMessage = null;
    }

    notifyListeners();
    return _errorMessage == null ? '$number' : null;
  }
}
