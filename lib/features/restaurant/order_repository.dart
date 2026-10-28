import '../../core/domain/order.dart';

/// Fila já traduzida para o ViewModel.
///
/// Não carrega status HTTP nem exceção de transporte. Lista vazia é sucesso:
/// [orders] vem vazio e [message] fica nula. Falha deixa [orders] nulo.
class OrderList {
  OrderList.ready(List<Order> orders) : this._(orders: List.unmodifiable(orders));

  const OrderList.unavailable(String message) : this._(message: message);

  const OrderList._({this.orders, this.message});

  /// `null` quando a listagem falhou. Lista vazia significa fila sem pedidos.
  final List<Order>? orders;

  /// Preenchida só quando a listagem falha.
  final String? message;
}

/// Fonte da fila de pedidos do restaurante.
///
/// A implementação concreta traduz o JSON de `GET /orders` e as falhas de
/// transporte para [OrderList]. O ViewModel depende deste contrato e ordena
/// a fila; este contrato devolve a lista na ordem recebida.
abstract interface class OrderRepository {
  Future<OrderList> list();
}
