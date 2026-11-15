import 'dart:async';

/// Atraso do polling que só termina quando o teste chama [elapse].
class ControllableDelay {
  Completer<void>? _pending;
  final durations = <Duration>[];

  Future<void> call(Duration duration) {
    durations.add(duration);
    final completer = Completer<void>();
    _pending = completer;
    return completer.future;
  }

  void elapse() {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      throw StateError('nenhum atraso pendente');
    }
    _pending = null;
    pending.complete();
  }
}
