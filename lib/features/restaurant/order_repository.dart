import '../../core/domain/data_failure.dart';
import '../../core/domain/order.dart';

/// Fila já traduzida para o ViewModel.
///
/// Não carrega status HTTP nem exceção de transporte. Lista vazia é sucesso:
/// [orders] vem vazio e [message] fica nula. Falha deixa [orders] nulo.
/// [failure] classifica essa falha para a apresentação.
class OrderList {
  OrderList.ready(List<Order> orders) : this._(orders: List.unmodifiable(orders));

  const OrderList.unavailable(
    String message, {
    DataFailure failure = DataFailure.unavailable,
    String? detail,
  }) : this._(message: message, failure: failure, detail: detail);

  const OrderList._({this.orders, this.message, this.failure, this.detail});

  /// `null` quando a listagem falhou. Lista vazia significa fila sem pedidos.
  final List<Order>? orders;

  /// Preenchida só quando a listagem falha.
  final String? message;

  /// Nula quando a lista carregou.
  final DataFailure? failure;

  /// Causa técnica. A tela usa [message].
  final String? detail;
}

/// Fonte da fila de pedidos do restaurante.
///
/// A implementação concreta traduz o JSON de `GET /orders` e as falhas de
/// transporte para [OrderList]. O ViewModel depende deste contrato e ordena
/// a fila; este contrato devolve a lista na ordem recebida.
abstract interface class OrderRepository {
  Future<OrderList> list();
}
