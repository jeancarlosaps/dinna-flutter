import '../../core/domain/order.dart';

/// Id de produto ou de pedido passado em `RouteSettings.arguments`.
///
/// O router não lê este valor. A View da rota é quem valida.
final class AppRouteId {
  const AppRouteId(this.value);

  final String value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || (other is AppRouteId && other.value == value);
  }

  @override
  int get hashCode => value.hashCode;
}

/// Pedido já carregado na fila, junto com o [AppRouteId] da rota de detalhe.
///
/// A fila monta este argumento para o detalhe não repetir `GET /orders`.
/// O router não o interpreta: a View é quem valida.
final class RestaurantOrderArgs {
  const RestaurantOrderArgs({required this.id, required this.order});

  final AppRouteId id;
  final Order order;
}
