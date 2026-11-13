/// Larguras em que o painel do restaurante muda de coluna única para tablet.
abstract final class DinnaLayout {
  /// Abaixo disto: celular, uma coluna, formulário em página cheia.
  static const tablet = 900.0;

  static bool isTablet(double width) => width >= tablet;
}
