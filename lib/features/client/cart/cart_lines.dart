import '../../../core/domain/cart_item.dart';

/// Entrada e saída da revisão do carrinho.
///
/// [read] entrega as linhas externas. [replace] grava a lista inteira, na
/// mesma ordem, só quando [expected] ainda é a lista atual. Quem grava em
/// disco implementa este contrato. Esta tela não escolhe o mecanismo.
abstract interface class CartLines {
  List<CartItem> read();

  /// Grava [next] somente se a lista armazenada ainda for [expected].
  ///
  /// Devolve `false` sem gravar quando outra escrita aconteceu depois do
  /// [read]. A revisão não substitui essa lista mais nova.
  bool replace(List<CartItem> expected, List<CartItem> next);
}

/// Lista viva só enquanto o processo existe.
///
/// Não é a persistência da SCRUM-69. Não gera `lineId` e não sobrevive ao
/// fechamento do app. João substitui esta classe pela implementação que
/// restaura e grava. A tela continua em [CartLines.read] e [CartLines.replace].
final class ProcessCartLines implements CartLines {
  ProcessCartLines([List<CartItem> items = const []]) : _items = List<CartItem>.of(items);

  List<CartItem> _items;

  @override
  List<CartItem> read() => List<CartItem>.unmodifiable(_items);

  @override
  bool replace(List<CartItem> expected, List<CartItem> next) {
    if (!_sameSequence(_items, expected)) return false;
    _items = List<CartItem>.of(next);
    return true;
  }
}

bool _sameSequence(List<CartItem> current, List<CartItem> expected) {
  if (current.length != expected.length) return false;
  for (var index = 0; index < current.length; index++) {
    if (current[index] != expected[index]) return false;
  }
  return true;
}
