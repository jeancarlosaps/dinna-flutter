import 'package:flutter/material.dart';

import '../../core/domain/order_status.dart';

/// Número público com ao menos quatro dígitos. `#10000` não é cortado.
String formatPublicOrderNumber(int orderNumber) {
  if (orderNumber < 1) {
    throw ArgumentError.value(orderNumber, 'orderNumber', 'orderNumber deve ser >= 1');
  }
  return '#${orderNumber.toString().padLeft(4, '0')}';
}

/// Rótulo visível do pedido. Sem o número, não usa o identificador técnico.
String publicOrderLabel(int? orderNumber) {
  if (orderNumber == null) return 'Pedido confirmado';
  return 'Pedido ${formatPublicOrderNumber(orderNumber)}';
}

/// Horário local do pedido, no mesmo formato do card da fila: `dd/MM HH:mm`.
String formatOrderTimestamp(DateTime createdAt) {
  final local = createdAt.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

String orderStatusLabel(OrderStatus status) => switch (status) {
  OrderStatus.received => 'Recebido',
  OrderStatus.preparing => 'Preparando',
  OrderStatus.ready => 'Pronto',
  OrderStatus.finished => 'Finalizado',
};

/// Texto do botão de um toque. `null` quando não há próximo status.
String? orderAdvanceActionLabel(OrderStatus status) => switch (status) {
  OrderStatus.received => 'Iniciar preparo',
  OrderStatus.preparing => 'Marcar como pronto',
  OrderStatus.ready => 'Finalizar pedido',
  OrderStatus.finished => null,
};

Color orderStatusColor(ColorScheme scheme, OrderStatus status) => switch (status) {
  OrderStatus.received => scheme.primary,
  OrderStatus.preparing => scheme.tertiary,
  OrderStatus.ready => scheme.secondary,
  OrderStatus.finished => scheme.onSurfaceVariant,
};

Color orderStatusContainerColor(ColorScheme scheme, OrderStatus status) => switch (status) {
  OrderStatus.received => scheme.primaryContainer,
  OrderStatus.preparing => scheme.tertiaryContainer,
  OrderStatus.ready => scheme.secondaryContainer,
  OrderStatus.finished => scheme.surfaceContainerHighest,
};

String formatOrderItemCount(int count) => count == 1 ? '1 item' : '$count itens';

/// Nome exibido na cozinha. Sem catálogo, ainda deixa claro que é um produto.
String orderItemDisplayName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'Produto';
  return trimmed;
}

/// Observação limpa do item, ou `null` quando vazia.
String? orderItemNote(String? note) {
  final trimmed = note?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// `totalCents` do contrato, em reais. O model já garante valor >= 0.
String formatOrderTotal(int totalCents) {
  final whole = totalCents ~/ 100;
  final cents = (totalCents % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = end - 3 < 0 ? 0 : end - 3;
    groups.add(digits.substring(start, end));
  }
  return 'R\$ ${groups.reversed.join('.')},$cents';
}
