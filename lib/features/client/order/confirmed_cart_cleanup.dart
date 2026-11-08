import 'dart:async';

import '../../../core/domain/cart_item.dart';
import '../cart/cart_lines.dart';
import '../cart/cart_session.dart';
import 'order_submission_view_model.dart';

/// Esvazia a fotografia confirmada quando o pedido ficou gravado.
///
/// Falha de limpeza não apaga a intenção nem autoriza outro POST. Timeout,
/// HTTP 401 e envio incerto não entram: [OrderSubmissionViewModel.shouldClearCart]
/// continua falso.
final class ConfirmedCartCleanup {
  ConfirmedCartCleanup({required this.submission, this.session, this.lines});

  final OrderSubmissionViewModel submission;
  final CartSession? session;
  final CartLines? lines;
  String? _clearedFor;
  String? _subtractedFor;
  var _running = false;
  Future<bool>? _active;

  void attach() {
    submission.addListener(_onChanged);
    session?.addListener(_onChanged);
  }

  void detach() {
    submission.removeListener(_onChanged);
    session?.removeListener(_onChanged);
  }

  /// Tira a fotografia confirmada uma única vez e grava essa conclusão.
  ///
  /// Uma segunda chamada, inclusive depois de recriar o app, não subtrai de
  /// novo. `false` significa que o carrinho ainda não foi conciliado.
  Future<bool> reconcile() {
    final current = _active;
    if (current != null) return current;
    final intentId = submission.intentId;
    final items = submission.confirmedItems;
    if (!submission.shouldClearCart || intentId == null || items == null) {
      return Future.value(false);
    }
    if (submission.cartReconciled || _clearedFor == intentId) {
      _clearedFor = intentId;
      return Future.value(true);
    }
    final run = _clear(intentId, items);
    _active = run;
    return run.whenComplete(() {
      if (identical(_active, run)) _active = null;
    });
  }

  void _onChanged() {
    if (_running) return;
    final intentId = submission.intentId;
    final items = submission.confirmedItems;
    if (!submission.shouldClearCart || intentId == null || items == null) return;
    if (submission.cartReconciled || _clearedFor == intentId) {
      _clearedFor = intentId;
      return;
    }
    unawaited(reconcile());
  }

  Future<bool> _clear(String intentId, List<CartItem> items) async {
    _running = true;
    try {
      if (!submission.shouldClearCart || submission.intentId != intentId) return false;
      if (submission.cartReconciled) {
        _clearedFor = intentId;
        return true;
      }
      if (_subtractedFor != intentId) {
        final cart = session;
        if (cart != null) {
          if (!cart.isReady) {
            try {
              await cart.restore();
            } catch (_) {
              return false;
            }
          }
          if (!submission.shouldClearCart || submission.intentId != intentId) return false;
          await cart.removeConfirmed(items);
        } else {
          final memory = lines;
          if (memory != null) {
            final current = memory.read();
            final next = withoutConfirmedItems(current, items);
            if (!memory.replace(current, next)) return false;
          }
        }
        _subtractedFor = intentId;
      }
      if (!await submission.markCartReconciled()) return false;
      _clearedFor = intentId;
      return true;
    } catch (_) {
      // A confirmação gravada permanece. Outro POST continua bloqueado.
      return false;
    } finally {
      _running = false;
    }
  }
}

/// Replica a reconciliação do SQLite para o carrinho em memória.
///
/// Linha com o mesmo `lineId` e a mesma observação perde a quantidade enviada.
/// Sem `lineId`, o par produto e observação identifica a linha.
List<CartItem> withoutConfirmedItems(List<CartItem> current, List<CartItem> confirmed) {
  final pending = List<CartItem>.of(current);
  final seen = <String>{};
  for (final sent in confirmed) {
    final lineId = sent.lineId;
    if (lineId != null && !seen.add(lineId)) continue;
    final index = pending.indexWhere((item) => _sameLine(item, sent));
    if (index < 0) continue;
    final item = pending[index];
    final remaining = item.quantity - sent.quantity;
    if (remaining < 1) {
      pending.removeAt(index);
    } else {
      pending[index] = CartItem(
        lineId: item.lineId,
        productId: item.productId,
        quantity: remaining,
        note: item.note,
      );
    }
  }
  return List<CartItem>.unmodifiable(pending);
}

bool _sameLine(CartItem current, CartItem sent) {
  final lineId = sent.lineId;
  if (lineId != null) return current.lineId == lineId && current.note == sent.note;
  return current.productId == sent.productId && current.note == sent.note;
}
