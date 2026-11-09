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

/// Abertura do carrinho. [reviewOnly] impede a confirmação automática.
///
/// A mesa continua opcional. Sem este objeto, a rota aceita a mesa como [String].
final class CartRouteArgs {
  const CartRouteArgs({this.table, this.reviewOnly = false});

  final String? table;
  final bool reviewOnly;
}

/// Acompanhamento de um pedido já confirmado.
///
/// [id] permanece o identificador técnico da rota. [orderNumber] é o número
/// público, quando ele já veio na resposta. A tela não consulta a API.
final class OrderTrackingArgs {
  const OrderTrackingArgs({required this.id, this.orderNumber});

  final AppRouteId id;
  final int? orderNumber;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is OrderTrackingArgs && other.id == id && other.orderNumber == orderNumber);
  }

  @override
  int get hashCode => Object.hash(id, orderNumber);
}

/// Pedido que a API já confirmou e o envio gravou.
///
/// A confirmação lê este valor e não repete `POST /orders` nem `GET /orders`.
/// O router não o interpreta: a View é quem valida.
final class OrderConfirmationArgs {
  const OrderConfirmationArgs({required this.order});

  final Order order;
}
