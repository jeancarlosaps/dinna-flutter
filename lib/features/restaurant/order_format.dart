import 'package:flutter/material.dart';

import '../../core/domain/order_status.dart';

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

Color orderStatusColor(ColorScheme scheme, OrderStatus status) => switch (status) {
  OrderStatus.received => scheme.primary,
  OrderStatus.preparing => scheme.tertiary,
  OrderStatus.ready => scheme.secondary,
  OrderStatus.finished => scheme.onSurfaceVariant,
};

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
