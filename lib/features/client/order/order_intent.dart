import '../../../core/domain/cart_item.dart';
import '../../../core/domain/json_values.dart';
import '../../../core/domain/order.dart';
import 'order_intent_id.dart';

/// Fase da intenção guardada no aparelho.
enum OrderIntentPhase { pending, uncertain, succeeded, blocked }

/// Motivo pelo qual a intenção não pode ser reenviada nem substituída.
enum OrderIntentBlock { conflict, invalidState, expired }

/// Uma tentativa de `POST /orders`: chave, body e o instante em que nasceu.
///
/// O body é imutável. Quantidade, observação e ordem dos itens ficam como
/// estavam no primeiro envio. A retenção da API é [retention]. O app deixa
/// de reenviar [resumeSafetyMargin] antes, porque o relógio do aparelho pode
/// estar adiantado em relação ao servidor.
final class OrderIntent {
  OrderIntent({
    required this.id,
    required this.createdAt,
    required this.phase,
    required this.table,
    required List<Map<String, Object?>> items,
    this.block,
    this.order,
  }) : items = List<Map<String, Object?>>.unmodifiable([
         // Map.unmodifiable é uma vista. A cópia impede que o mapa do
         // chamador altere o body ligado a esta chave.
         for (final item in items) Map<String, Object?>.unmodifiable(Map<String, Object?>.of(item)),
       ]) {
    if (!orderIntentIdPattern.hasMatch(id) || _isNilUuid(id)) {
      throw FormatException('id de intenção inválido');
    }
    if (!createdAt.isUtc) {
      throw FormatException('createdAt da intenção deve estar em UTC');
    }
    if (table.trim().isEmpty) {
      throw FormatException('mesa da intenção vazia');
    }
    if (items.isEmpty) {
      throw FormatException('intenção sem itens');
    }
    if (phase == OrderIntentPhase.blocked && block == null) {
      throw FormatException('intenção bloqueada sem motivo');
    }
    if (phase != OrderIntentPhase.blocked && block != null) {
      throw FormatException('motivo de bloqueio fora de uma intenção bloqueada');
    }
    if (phase == OrderIntentPhase.succeeded && order == null) {
      throw FormatException('intenção concluída sem pedido');
    }
    for (final item in this.items) {
      // Valida o domínio e preserva o mapa original, inclusive note omitida.
      CartItem.fromJson(item);
    }
  }

  /// Janela em que a API devolve o pedido original para a mesma chave.
  static const retention = Duration(hours: 24);

  /// Folga antes do fim de [retention]. Dentro dela o app não reenvia.
  static const resumeSafetyMargin = Duration(hours: 1);

  final String id;
  final DateTime createdAt;
  final OrderIntentPhase phase;
  final String table;
  final List<Map<String, Object?>> items;
  final OrderIntentBlock? block;
  final Order? order;

  factory OrderIntent.pending({
    required String id,
    required DateTime createdAt,
    required String table,
    required List<Map<String, Object?>> items,
  }) {
    return OrderIntent(
      id: id,
      createdAt: createdAt,
      phase: OrderIntentPhase.pending,
      table: table,
      items: items,
    );
  }

  factory OrderIntent.fromJson(Object? json) {
    final map = readJsonObject(json, 'OrderIntent');
    final phaseName = readRequiredString(map, 'phase');
    final phase = _phase(phaseName);
    final block = _block(map['block']);
    final orderValue = map['order'];
    return OrderIntent(
      id: readRequiredString(map, 'id'),
      createdAt: readRequiredUtc(map, 'createdAt'),
      phase: phase,
      table: readRequiredString(map, 'table'),
      items: _items(map['items']),
      block: block,
      order: orderValue == null ? null : Order.fromJson(orderValue),
    );
  }

  /// `true` enquanto a chave ainda cabe na folga de segurança.
  ///
  /// Instante no futuro ou idade maior ou igual a [retention] menos
  /// [resumeSafetyMargin] não autoriza outro POST.
  bool allowsResume(DateTime now) {
    final clock = now.toUtc();
    if (createdAt.isAfter(clock)) return false;
    final limit = retention - resumeSafetyMargin;
    return clock.difference(createdAt) < limit;
  }

  Map<String, Object?> get body => {
    'table': table,
    'items': <Object?>[for (final item in items) Map<String, Object?>.of(item)],
  };

  List<CartItem> get cartItems => List<CartItem>.unmodifiable([
    for (final item in items)
      CartItem(
        productId: item['productId']! as String,
        quantity: item['quantity']! as int,
        note: item.containsKey('note') ? item['note'] as String? : null,
      ),
  ]);

  OrderIntent uncertain() {
    return OrderIntent(
      id: id,
      createdAt: createdAt,
      phase: OrderIntentPhase.uncertain,
      table: table,
      items: items,
    );
  }

  OrderIntent succeeded(Order order) {
    return OrderIntent(
      id: id,
      createdAt: createdAt,
      phase: OrderIntentPhase.succeeded,
      table: table,
      items: items,
      order: order,
    );
  }

  OrderIntent blocked(OrderIntentBlock reason) {
    return OrderIntent(
      id: id,
      createdAt: createdAt,
      phase: OrderIntentPhase.blocked,
      table: table,
      items: items,
      block: reason,
      order: order,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': writeUtcIso8601(createdAt),
    'phase': phase.name,
    'table': table,
    'items': <Object?>[for (final item in items) Map<String, Object?>.of(item)],
    if (block != null) 'block': block!.name,
    if (order != null) 'order': order!.toJson(),
  };
}

bool _isNilUuid(String id) => id.toLowerCase() == '00000000-0000-0000-0000-000000000000';

OrderIntentPhase _phase(String name) {
  for (final phase in OrderIntentPhase.values) {
    if (phase.name == name) return phase;
  }
  throw FormatException('fase de intenção desconhecida');
}

OrderIntentBlock? _block(Object? value) {
  if (value == null) return null;
  if (value is! String) throw FormatException('motivo de bloqueio inválido');
  for (final block in OrderIntentBlock.values) {
    if (block.name == value) return block;
  }
  throw FormatException('motivo de bloqueio desconhecido');
}

List<Map<String, Object?>> _items(Object? value) {
  if (value is! List || value.isEmpty) {
    throw FormatException('itens da intenção inválidos');
  }
  final items = <Map<String, Object?>>[];
  for (final raw in value) {
    if (raw is! Map) throw FormatException('item da intenção inválido');
    final item = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) throw FormatException('campo de item inválido');
      item[entry.key as String] = entry.value as Object?;
    }
    final productId = item['productId'];
    final quantity = item['quantity'];
    if (productId is! String || productId.trim().isEmpty || quantity is! int || quantity < 1) {
      throw FormatException('item da intenção inválido');
    }
    final note = item['note'];
    if (item.containsKey('note') && note is! String) {
      throw FormatException('observação da intenção inválida');
    }
    items.add(item);
  }
  return items;
}
