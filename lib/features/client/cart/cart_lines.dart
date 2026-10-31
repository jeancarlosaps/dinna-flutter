import '../../../core/domain/cart_item.dart';

/// Entrada e saída da revisão do carrinho.
///
/// [read] entrega as linhas externas quando a tela abre. [write] recebe a
/// lista inteira, na mesma ordem, depois de cada alteração. Quem grava em
/// disco implementa este contrato. Esta tela não escolhe o mecanismo.
abstract interface class CartLines {
  List<CartItem> read();

  void write(List<CartItem> items);
}

/// Lista viva só enquanto o processo existe.
///
/// Não é a persistência da SCRUM-69. Não gera `lineId` e não sobrevive ao
/// fechamento do app. João substitui esta classe pela implementação que
/// restaura e grava. A tela continua em [CartLines.read] e [CartLines.write].
final class ProcessCartLines implements CartLines {
  ProcessCartLines([List<CartItem> items = const []]) : _items = List<CartItem>.of(items);

  List<CartItem> _items;

  @override
  List<CartItem> read() => List<CartItem>.unmodifiable(_items);

  @override
  void write(List<CartItem> items) {
    _items = List<CartItem>.of(items);
  }
}
