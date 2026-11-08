import '../../../core/domain/cart_item.dart';
import '../../../core/domain/json_values.dart';
import '../../../core/domain/order.dart';
import 'order_intent_id.dart';

/// Fase da intenção guardada no aparelho.
enum OrderIntentPhase { pending, uncertain, succeeded, blocked }

/// Motivo pelo qual a intenção não pode ser reenviada nem substituída.
enum OrderIntentBlock { conflict, invalidState, expired }

/// Rejeição definitiva que conserva a mesma chave e o mesmo payload.
enum OrderIntentRejection { unauthorized }

/// Uma tentativa de `POST /orders`: chave, body e o instante em que nasceu.
///
/// O body é imutável. Quantidade, observação e ordem dos itens ficam como
/// estavam no primeiro envio. A API mantém a chave enquanto a linha existir
/// em `idempotency_keys`. [retention] menos [resumeSafetyMargin] é uma folga
/// local de 23 horas: cobre intenção anterior à retenção permanente, chave
/// apagada por um servidor antigo e relógio adiantado. Não é prazo do
/// servidor, não lê `Idempotency-Retention` e não garante relógio correto.
final class OrderIntent {
  OrderIntent({
    required this.id,
    required this.createdAt,
    required this.phase,
    required this.table,
    required List<Map<String, Object?>> items,
    this.block,
    this.order,
    this.rejection,
    this.cartReconciled = false,
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
    if (rejection != null && phase != OrderIntentPhase.pending) {
      throw FormatException('rejeição fora de uma intenção pendente');
    }
    if (cartReconciled && phase != OrderIntentPhase.succeeded) {
      throw FormatException('conciliação do carrinho fora de uma intenção concluída');
    }
    for (final item in this.items) {
      // Valida o domínio e preserva o mapa original, inclusive note omitida.
      CartItem.fromJson(item);
    }
  }

  /// Teto local da folga. A API atual não expira a chave neste prazo.
  static const retention = Duration(hours: 24);

  /// Folga antes do fim de [retention]. A partir dela o app não reenvia.
  static const resumeSafetyMargin = Duration(hours: 1);

  final String id;
  final DateTime createdAt;
  final OrderIntentPhase phase;
  final String table;
  final List<Map<String, Object?>> items;
  final OrderIntentBlock? block;
  final Order? order;

  /// Preenchida quando a API recusou o acesso e a mesma tentativa continua válida.
  final OrderIntentRejection? rejection;

  /// A fotografia confirmada já saiu do carrinho uma vez.
  final bool cartReconciled;

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
      rejection: _rejection(map['rejection']),
      cartReconciled: _cartReconciled(map['cartReconciled']),
    );
  }

  /// `true` enquanto a chave ainda cabe na folga local de 23 horas.
  ///
  /// Instante no futuro ou idade maior ou igual a [retention] menos
  /// [resumeSafetyMargin] não autoriza outro POST. O header
  /// `Idempotency-Retention` não entra nesta conta.
  bool allowsResume(DateTime now) {
    final clock = now.toUtc();
    if (createdAt.isAfter(clock)) return false;
    final limit = retention - resumeSafetyMargin;
    return clock.difference(createdAt) < limit;
  }

  Map<String, Object?> get body => {
    'table': table,
    'items': <Object?>[
      for (final item in items)
        {
          'productId': item['productId'],
          'quantity': item['quantity'],
          if (item.containsKey('note')) 'note': item['note'],
        },
    ],
  };

  List<CartItem> get cartItems =>
      List<CartItem>.unmodifiable([for (final item in items) CartItem.fromJson(item)]);

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

  OrderIntent refused(OrderIntentRejection reason) {
    return OrderIntent(
      id: id,
      createdAt: createdAt,
      phase: OrderIntentPhase.pending,
      table: table,
      items: items,
      rejection: reason,
    );
  }

  OrderIntent withCartReconciled() {
    return OrderIntent(
      id: id,
      createdAt: createdAt,
      phase: phase,
      table: table,
      items: items,
      block: block,
      order: order,
      rejection: rejection,
      cartReconciled: true,
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
    if (rejection != null) 'rejection': rejection!.name,
    if (cartReconciled) 'cartReconciled': true,
  };
}

bool _isNilUuid(String id) => id.toLowerCase() == '00000000-0000-0000-0000-000000000000';

OrderIntentPhase _phase(String name) {
  for (final phase in OrderIntentPhase.values) {
    if (phase.name == name) return phase;
  }
  throw FormatException('fase de intenção desconhecida');
}

bool _cartReconciled(Object? value) {
  if (value == null) return false;
  if (value is! bool) throw FormatException('conciliação do carrinho inválida');
  return value;
}

OrderIntentRejection? _rejection(Object? value) {
  if (value == null) return null;
  if (value is! String) throw FormatException('rejeição da intenção inválida');
  for (final rejection in OrderIntentRejection.values) {
    if (rejection.name == value) return rejection;
  }
  throw FormatException('rejeição da intenção desconhecida');
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
